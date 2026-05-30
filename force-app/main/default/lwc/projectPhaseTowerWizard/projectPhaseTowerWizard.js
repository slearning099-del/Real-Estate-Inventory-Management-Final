/**
 * projectPhaseTowerWizard.js
 *
 * High-performance wizard for creating up to 200 Tower__c records.
 *
 * Performance strategies
 * ──────────────────────
 * 1. VIRTUAL WINDOW  – Only PAGE_SIZE (10) tower cards are rendered in the
 *    DOM at any time.  Prev/Next page buttons scroll through the full list
 *    without ever mounting 200 lightning-input components simultaneously.
 *
 * 2. FLAT DATA STORE – towerData[] is a plain JS array (not @track).
 *    Individual field changes mutate the array in-place; only the visible
 *    window slice (visibleTowers) is @track-reactive, so LWC re-renders
 *    at most PAGE_SIZE cards per change.
 *
 * 3. DEBOUNCED VALIDATION – isNextDisabled / isSaveDisabled are computed
 *    lazily from a cached dirty-flag counter rather than scanning the full
 *    array on every keystroke.
 *
 * 4. CHUNKED APEX – The Apex controller inserts in chunks of 200 rows,
 *    staying well within DML governor limits.
 */

import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent }        from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import getProjectPhaseDetails    from '@salesforce/apex/ProjectPhaseTowerWizardController.getProjectPhaseDetails';
import checkExistingTowers       from '@salesforce/apex/ProjectPhaseTowerWizardController.checkExistingTowers';
import createTowers              from '@salesforce/apex/ProjectPhaseTowerWizardController.createTowers';

// ── Constants ────────────────────────────────────────────────────────────────
const MAX_TOWERS  = 200;   // hard cap (matches Apex)
const PAGE_SIZE   = 10;    // cards visible in the DOM at once

const STATUS_CLASS_MAP = {
    'Planning'             : 'rbadge rbadge--planning',
    'Finishing Stage'      : 'rbadge rbadge--finishing',
    'Ready For possession' : 'rbadge rbadge--ready',
    'Handover Progress'    : 'rbadge rbadge--handover',
    'On Hold'              : 'rbadge rbadge--hold',
};

// ── Component ────────────────────────────────────────────────────────────────
export default class ProjectPhaseTowerWizard extends LightningElement {

    @api recordId;

    // ── UI state ─────────────────────────────────────────────────
    @track isLoading          = true;
    @track towersAlreadyExist = false;
    @track currentStep        = 'step1';
    @track projectPhase       = {};

    // ── Step-2 state ─────────────────────────────────────────────
    @track wantTowers    = false;   // toggle
    @track numberOfTowers = 0;

    /**
     * towerData  – source of truth for ALL tower rows.
     * Plain array, NOT @track.  Mutations are cheap; only the
     * visible slice is reactive.
     */
    towerData = [];

    /** Number of rows with a blank Name (dirty counter). */
    _emptyNameCount = 0;

    // ── Virtual-window state ─────────────────────────────────────
    @track _currentPage  = 0;   // 0-based page index
    @track visibleTowers = [];  // the PAGE_SIZE slice shown in DOM

    // ── Picklist options (static) ─────────────────────────────────
    statusOptions = [
        { label: 'Planning',              value: 'Planning'              },
        { label: 'Finishing Stage',       value: 'Finishing Stage'       },
        { label: 'Ready For possession',  value: 'Ready For possession'  },
        { label: 'Handover Progress',     value: 'Handover Progress'     },
        { label: 'On Hold',               value: 'On Hold'               },
    ];

    // ════════════════════════════════════════════════════════════════
    //  Lifecycle
    // ════════════════════════════════════════════════════════════════
    connectedCallback() {
        this._loadData();
    }

    async _loadData() {
        try {
            this.isLoading = true;
            const exists = await checkExistingTowers({ projectPhaseId: this.recordId });
            if (exists) {
                this.towersAlreadyExist = true;
                this.isLoading = false;
                return;
            }
            this.projectPhase = await getProjectPhaseDetails({ projectPhaseId: this.recordId });
            this.isLoading = false;
        } catch (err) {
            this.isLoading = false;
            this._toast('Error', this._errMsg(err), 'error');
        }
    }

    // ════════════════════════════════════════════════════════════════
    //  Step getters
    // ════════════════════════════════════════════════════════════════
    get isStep1() { return this.currentStep === 'step1'; }
    get isStep2() { return this.currentStep === 'step2'; }
    get isStep3() { return this.currentStep === 'step3'; }

    get currentStepNumber() {
        return this.currentStep === 'step1' ? 1 : this.currentStep === 'step2' ? 2 : 3;
    }

    get step1Class() {
        return this.currentStep === 'step1' ? 'path-step path-step--active' : 'path-step path-step--done';
    }
    get step2Class() {
        if (this.currentStep === 'step1') return 'path-step';
        if (this.currentStep === 'step2') return 'path-step path-step--active';
        return 'path-step path-step--done';
    }
    get step3Class() {
        return this.currentStep === 'step3' ? 'path-step path-step--active' : 'path-step';
    }
    get isStep1Done() { return this.currentStep !== 'step1'; }
    get isStep2Done() { return this.currentStep === 'step3'; }

    get statusBadgeClass() { return 'status-badge'; }

    // ════════════════════════════════════════════════════════════════
    //  Step-2 computed
    // ════════════════════════════════════════════════════════════════
    get showTowerForms() {
        return this.wantTowers && this.numberOfTowers > 0 && this.towerData.length > 0;
    }

    /** Disable Next only when names are missing */
    get isNextDisabled() {
        if (!this.isStep2) return false;
        if (!this.wantTowers || this.numberOfTowers <= 0) return true;
        return this._emptyNameCount > 0;
    }

    get isSaveDisabled() {
        return this.towerData.length === 0 || this._emptyNameCount > 0;
    }

    // ── Virtual window pagination ─────────────────────────────────
    get totalPages() {
        return Math.ceil(this.towerData.length / PAGE_SIZE) || 1;
    }
    get isPrevPageDisabled() { return !this._currentPage > 0; }
    get isNextPageDisabled() { return !(this._currentPage < this.totalPages - 1); }
    get hasPrevPage() { return this._currentPage > 0; }
    get hasNextPage()  { return this._currentPage < this.totalPages - 1; }

    get pageLabel() {
        const start = this._currentPage * PAGE_SIZE + 1;
        const end   = Math.min(start + PAGE_SIZE - 1, this.towerData.length);
        return `Showing ${start}–${end} of ${this.towerData.length}`;
    }

    // ── Review list (all rows, lightweight objects) ───────────────
    get reviewList() {
        return this.towerData.map(t => ({
            index       : t.index,
            displayIndex: t.displayIndex,
            Name        : t.Name,
            Status__c   : t.Status__c,
            statusClass : t.statusClass,
        }));
    }

    // ════════════════════════════════════════════════════════════════
    //  Toggle handler
    // ════════════════════════════════════════════════════════════════
    handleCreateTowersChange(event) {
        this.wantTowers = event.target.checked;
        if (!this.wantTowers) {
            this.numberOfTowers  = 0;
            this.towerData       = [];
            this._emptyNameCount = 0;
            this.visibleTowers   = [];
            this._currentPage    = 0;
        }
    }

    // ════════════════════════════════════════════════════════════════
    //  Number-of-towers input
    // ════════════════════════════════════════════════════════════════
    handleNumberOfTowersChange(event) {
        let val = parseInt(event.target.value, 10);
        if (isNaN(val) || val < 1) {
            this.numberOfTowers  = 0;
            this.towerData       = [];
            this._emptyNameCount = 0;
            this.visibleTowers   = [];
            this._currentPage    = 0;
            return;
        }
        if (val > MAX_TOWERS) {
            val = MAX_TOWERS;
            this._toast('Warning', `Maximum ${MAX_TOWERS} towers allowed.`, 'warning');
        }
        this.numberOfTowers = val;
        this._buildTowerData(val);
    }

    /**
     * Build the flat towerData array and show page 0.
     * O(n) but only called when the count field changes, not on every keystroke.
     */
    _buildTowerData(count) {
        const arr = new Array(count);
        for (let i = 0; i < count; i++) {
            arr[i] = {
                index        : i,
                displayIndex : i + 1,
                Name         : '',
                Status__c    : 'Planning',
                statusClass  : 'rbadge rbadge--planning',
            };
        }
        this.towerData       = arr;
        this._emptyNameCount = count;   // all names blank initially
        this._currentPage    = 0;
        this._refreshWindow();
    }

    // ════════════════════════════════════════════════════════════════
    //  Tower field handlers  (mutate in-place, refresh window only)
    // ════════════════════════════════════════════════════════════════
    handleTowerNameChange(event) {
        const idx      = parseInt(event.target.dataset.index, 10);
        const newVal   = event.target.value;
        const row      = this.towerData[idx];
        const wasEmpty = !row.Name || row.Name.trim() === '';
        const isEmpty  = !newVal || newVal.trim() === '';

        row.Name = newVal;

        // Update dirty counter
        if (wasEmpty && !isEmpty)  this._emptyNameCount--;
        if (!wasEmpty && isEmpty)  this._emptyNameCount++;

        // Refresh only the visible window (not the full array)
        this._refreshWindow();
    }

    handleTowerStatusChange(event) {
        const idx    = parseInt(event.target.dataset.index, 10);
        const status = event.target.value;
        this.towerData[idx].Status__c  = status;
        this.towerData[idx].statusClass = STATUS_CLASS_MAP[status] || 'rbadge rbadge--default';
        this._refreshWindow();
    }

    // ════════════════════════════════════════════════════════════════
    //  Virtual window helpers
    // ════════════════════════════════════════════════════════════════
    _refreshWindow() {
        const start = this._currentPage * PAGE_SIZE;
        const end   = Math.min(start + PAGE_SIZE, this.towerData.length);
        // Shallow-copy the slice so LWC detects the change
        this.visibleTowers = this.towerData.slice(start, end).map(t => ({ ...t }));
    }

    handlePrevPage() {
        if (this._currentPage > 0) {
            this._currentPage--;
            this._refreshWindow();
        }
    }

    handleNextPage() {
        if (this._currentPage < this.totalPages - 1) {
            this._currentPage++;
            this._refreshWindow();
        }
    }

    // ════════════════════════════════════════════════════════════════
    //  Wizard navigation
    // ════════════════════════════════════════════════════════════════
    handleNext() {
        if (this.isStep1) {
            this.currentStep = 'step2';
        } else if (this.isStep2 && this._validateStep2()) {
            this.currentStep = 'step3';
        }
    }

    handlePrevious() {
        if (this.isStep3)      this.currentStep = 'step2';
        else if (this.isStep2) this.currentStep = 'step1';
    }

    _validateStep2() {
        if (!this.wantTowers) {
            this._toast('Warning', 'Enable the toggle to create towers.', 'warning');
            return false;
        }
        if (this.numberOfTowers <= 0) {
            this._toast('Warning', 'Enter the number of towers to create.', 'warning');
            return false;
        }
        if (this._emptyNameCount > 0) {
            this._toast('Warning', `${this._emptyNameCount} tower name(s) are still empty.`, 'warning');
            return false;
        }
        return true;
    }

    // ════════════════════════════════════════════════════════════════
    //  Save
    // ════════════════════════════════════════════════════════════════
    async handleSave() {
        try {
            this.isLoading = true;

            // Build lean sObject list — no extra UI fields
            const payload = this.towerData.map(t => ({
                Name             : t.Name,
                Status__c        : t.Status__c,
                Project__c       : this.projectPhase.Project__c,
                Project_Phase__c : this.recordId,
            }));

            const result = await createTowers({ towers: payload });

            this.isLoading = false;

            if (result.success) {
                this._toast(
                    'Success',
                    `${result.successCount} tower(s) created successfully!`,
                    'success'
                );
                this.dispatchEvent(new CloseActionScreenEvent());
                // Refresh the record page
                // eslint-disable-next-line no-eval
                eval("$A.get('e.force:refreshView').fire();");
            } else {
                // Partial success — show first few errors
                const preview = result.errors.slice(0, 3).join('\n');
                const more    = result.errors.length > 3
                    ? `\n…and ${result.errors.length - 3} more.` : '';
                this._toast(
                    `Partial Success (${result.successCount} saved, ${result.errorCount} failed)`,
                    preview + more,
                    'warning'
                );
            }
        } catch (err) {
            this.isLoading = false;
            this._toast('Error', this._errMsg(err), 'error');
        }
    }

    // ════════════════════════════════════════════════════════════════
    //  Utilities
    // ════════════════════════════════════════════════════════════════
    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _errMsg(error) {
        if (error?.body?.message)                          return error.body.message;
        if (error?.body?.pageErrors?.[0]?.message)        return error.body.pageErrors[0].message;
        if (error?.body?.fieldErrors) {
            const fe = Object.values(error.body.fieldErrors);
            if (fe.length && fe[0].length) return fe[0][0].message;
        }
        return error?.message ?? 'An unknown error occurred.';
    }
}