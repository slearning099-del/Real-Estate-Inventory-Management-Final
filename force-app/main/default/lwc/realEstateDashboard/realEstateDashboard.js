/**
 * @description Real Estate CRM Dashboard LWC Controller
 *
 * Features:
 *  - Single Apex call returns full payload (summary + KPI + tower inventory + filter options)
 *  - Lazy-loads phase/tower options on filter change to minimise server calls
 *  - Pure CSS bar chart (no external library dependency)
 *  - Stacked progress bars on tower detail cards
 *  - Toast notifications for errors and refresh confirmation
 *
 * @author  RealEstate Dev Team
 * @version 1.0
 */
import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDashboardData    from '@salesforce/apex/RealEstateDashboardController.getDashboardData';
import getPhasesByProject  from '@salesforce/apex/RealEstateDashboardController.getPhasesByProject';
import getTowersByPhase    from '@salesforce/apex/RealEstateDashboardController.getTowersByPhase';
import getUnitsByTowerAndStatus from '@salesforce/apex/RealEstateDashboardController.getUnitsByTowerAndStatus';

// Chart bar max height in px – used to compute bar heights proportionally
const BAR_MAX_HEIGHT = 180;

export default class RealEstateDashboard extends NavigationMixin(LightningElement) {

    // ─────────────────────────────────────────────────────────────────────────
    //  TRACKED STATE
    // ─────────────────────────────────────────────────────────────────────────

    @api cardTitle = 'Real Estate CRM Dashboard';

    @track isLoading       = true;
    @track hasError        = false;
    @track errorMessage    = '';
    @track hasData         = false;

    // Filter values
    @track selectedProject = '';
    @track selectedPhase   = '';
    @track selectedTower   = '';
    @track startDate       = '';
    @track endDate         = '';

    // Applied filter values (sent to Apex)
    @track appliedProject  = null;
    @track appliedPhase    = null;
    @track appliedTower    = null;
    @track appliedStart    = null;
    @track appliedEnd      = null;

    // Data
    @track summaryData     = {};
    @track kpiData         = {};
    @track towerInventory  = [];
    @track projectOptions  = [];
    @track phaseOptions    = [{ label: '-- All Phases --', value: '' }];
    @track towerOptions    = [{ label: '-- All Towers --', value: '' }];

    lastUpdatedLabel = '';

    // ── Drill-down modal state ────────────────────────────────────────────
    @track isModalOpen      = false;
    @track modalTitle       = '';
    @track modalStatusClass = '';
    @track modalUnits       = [];
    @track isModalLoading   = false;

    // lightning-datatable column definitions for the modal
    unitColumns = [
        { label: 'Unit Code',    fieldName: 'unitCode',    type: 'text',     initialWidth: 120 },
        { label: 'Unit Name',    fieldName: 'name',        type: 'text' },
        { label: 'Status',       fieldName: 'status',      type: 'text',     initialWidth: 110,
          cellAttributes: { class: { fieldName: 'statusClass' } } },
        { label: 'Area (SqFt)',  fieldName: 'areaSqft',    type: 'number',   initialWidth: 110,
          typeAttributes: { minimumFractionDigits: 0, maximumFractionDigits: 0 } },
        { label: 'Base Price',   fieldName: 'basePrice',   type: 'currency', initialWidth: 130,
          typeAttributes: { currencyCode: 'INR', minimumFractionDigits: 0 } },
        { label: 'Final Amount', fieldName: 'finalAmount', type: 'currency', initialWidth: 130,
          typeAttributes: { currencyCode: 'INR', minimumFractionDigits: 0 } },
        { label: 'View Type',    fieldName: 'viewType',    type: 'text',     initialWidth: 110 }
    ];

    // ─────────────────────────────────────────────────────────────────────────
    //  LIFECYCLE
    // ─────────────────────────────────────────────────────────────────────────

    connectedCallback() {
        this.loadDashboard();
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  DATA LOADING
    // ─────────────────────────────────────────────────────────────────────────

    loadDashboard() {
        this.isLoading = true;
        this.hasError  = false;

        getDashboardData({
            projectId:      this.appliedProject  || null,
            projectPhaseId: this.appliedPhase    || null,
            towerId:        this.appliedTower    || null,
            startDate:      this.appliedStart    || null,
            endDate:        this.appliedEnd      || null
        })
        .then(payload => {
            this.processPayload(payload);
            this.isLoading = false;
            this.hasData   = true;
            this.lastUpdatedLabel = new Date().toLocaleTimeString();
        })
        .catch(error => {
            this.isLoading    = false;
            this.hasData      = false;
            this.hasError     = true;
            this.errorMessage = this.extractErrorMessage(error);
            this.showToast('Error', this.errorMessage, 'error');
        });
    }

    processPayload(payload) {
        this.summaryData    = payload.summary       || {};
        this.kpiData        = payload.kpi           || {};
        this.towerInventory = payload.towerInventory || [];
        this.projectOptions = payload.projectOptions || [];

        // Only overwrite phase/tower options if we haven't already lazy-loaded them
        if (!this.appliedProject && !this.appliedPhase) {
            this.phaseOptions = payload.projectPhaseOptions || [];
            this.towerOptions = payload.towerOptions        || [];
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  FILTER HANDLERS
    // ─────────────────────────────────────────────────────────────────────────

    handleProjectChange(event) {
        this.selectedProject = event.detail.value;
        this.selectedPhase   = '';
        this.selectedTower   = '';

        // Lazy-load phases for the selected project
        const projId = this.selectedProject || null;
        getPhasesByProject({ projectId: projId })
            .then(opts => { this.phaseOptions = opts; })
            .catch(() => {});

        // Reset tower options
        getTowersByPhase({ projectId: projId, projectPhaseId: null })
            .then(opts => { this.towerOptions = opts; })
            .catch(() => {});
    }

    handlePhaseChange(event) {
        this.selectedPhase = event.detail.value;
        this.selectedTower = '';

        // Lazy-load towers for the selected phase
        getTowersByPhase({
            projectId:      this.selectedProject || null,
            projectPhaseId: this.selectedPhase   || null
        })
        .then(opts => { this.towerOptions = opts; })
        .catch(() => {});
    }

    handleTowerChange(event) {
        this.selectedTower = event.detail.value;
    }

    handleStartDateChange(event) {
        this.startDate = event.detail.value;
    }

    handleEndDateChange(event) {
        this.endDate = event.detail.value;
    }

    handleApplyFilters() {
        // Validate date range
        if (this.startDate && this.endDate && this.startDate > this.endDate) {
            this.showToast('Validation Error', '"From Date" cannot be after "To Date".', 'warning');
            return;
        }

        this.appliedProject = this.selectedProject || null;
        this.appliedPhase   = this.selectedPhase   || null;
        this.appliedTower   = this.selectedTower   || null;
        this.appliedStart   = this.startDate       || null;
        this.appliedEnd     = this.endDate         || null;

        this.loadDashboard();
    }

    handleClearFilters() {
        this.selectedProject = '';
        this.selectedPhase   = '';
        this.selectedTower   = '';
        this.startDate       = '';
        this.endDate         = '';
        this.appliedProject  = null;
        this.appliedPhase    = null;
        this.appliedTower    = null;
        this.appliedStart    = null;
        this.appliedEnd      = null;

        // Reset lazy-loaded options
        this.phaseOptions = [{ label: '-- All Phases --', value: '' }];
        this.towerOptions = [{ label: '-- All Towers --', value: '' }];

        this.loadDashboard();
    }

    handleRefresh() {
        this.loadDashboard();
        this.showToast('Refreshed', 'Dashboard data has been refreshed.', 'success');
    }

    navigateToProjects() {
        // Placeholder – can be wired to NavigationMixin if needed
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  DRILL-DOWN MODAL
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Fired when a stat tile (Sold / Available / Hold / Booked) is clicked
     * on a Tower Detail Card.
     * Expected data attributes on the clicked element:
     *   data-tower-id   – Tower__c Id
     *   data-tower-name – Tower name (for modal title)
     *   data-status     – Property_unit_Status__c value
     */
    handleStatClick(event) {
        const towerId   = event.currentTarget.dataset.towerId;
        const towerName = event.currentTarget.dataset.towerName;
        const status    = event.currentTarget.dataset.status;

        if (!towerId || !status) return;

        // Status → CSS class for the modal badge
        const classMap = {
            'Sold':     'modal-status_green',
            'Available':'modal-status_blue',
            'Hold':     'modal-status_orange',
            'Booked':   'modal-status_purple',
            'Reserved': 'modal-status_purple'
        };

        this.modalTitle       = `${towerName} — ${status} Units`;
        this.modalStatusClass = classMap[status] || '';
        this.modalUnits       = [];
        this.isModalLoading   = true;
        this.isModalOpen      = true;

        getUnitsByTowerAndStatus({ towerId, status })
            .then(units => {
                this.modalUnits     = units.map(u => ({
                    ...u,
                    statusClass: classMap[u.status] ? `re-status-pill ${classMap[u.status]}` : ''
                }));
                this.isModalLoading = false;
            })
            .catch(err => {
                this.isModalLoading = false;
                this.isModalOpen    = false;
                this.showToast('Error', this.extractErrorMessage(err), 'error');
            });
    }

    /** Navigate to the individual Property_Unit__c record page */
    handleRowAction(event) {
        const row = event.detail.row;
        if (row && row.id) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId:   row.id,
                    objectApiName: 'Property_Unit__c',
                    actionName: 'view'
                }
            });
        }
    }

    handleModalClose() {
        this.isModalOpen  = false;
        this.modalUnits   = [];
        this.modalTitle   = '';
    }

    get hasModalUnits() {
        return this.modalUnits && this.modalUnits.length > 0;
    }

    get modalUnitCount() {
        return this.modalUnits ? this.modalUnits.length : 0;
    }

    /** Row actions column added to datatable */
    get unitColumnsWithAction() {
        return [
            ...this.unitColumns,
            {
                type: 'action',
                typeAttributes: {
                    rowActions: [{ label: 'View Record', name: 'view' }]
                }
            }
        ];
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  COMPUTED PROPERTIES – KPI progress bars
    // ─────────────────────────────────────────────────────────────────────────

    get soldBarStyle() {
        return this.barWidthStyle(this.kpiData.totalSold, this.kpiData.totalInventory);
    }

    get availableBarStyle() {
        return this.barWidthStyle(this.kpiData.totalAvailable, this.kpiData.totalInventory);
    }

    get holdBarStyle() {
        return this.barWidthStyle(this.kpiData.totalHold, this.kpiData.totalInventory);
    }

    get bookedBarStyle() {
        return this.barWidthStyle(this.kpiData.totalBooked, this.kpiData.totalInventory);
    }

    barWidthStyle(value, total) {
        const pct = total > 0 ? Math.round((value / total) * 100) : 0;
        return `width: ${pct}%`;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  COMPUTED PROPERTIES – Sales donut SVG
    // ─────────────────────────────────────────────────────────────────────────

    get salesDonutDash() {
        const pct = parseFloat(this.kpiData.salesPercentage) || 0;
        const circumference = 100; // SVG units
        const filled = (pct / 100) * circumference;
        return `${filled} ${circumference - filled}`;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  COMPUTED PROPERTIES – Tower table data
    // ─────────────────────────────────────────────────────────────────────────

    get towerTableData() {
        return (this.towerInventory || []).map(t => {
            const total  = t.totalFlats     || 0;
            const sold   = t.soldFlats      || 0;
            const avail  = t.availableFlats || 0;
            const hold   = t.holdFlats      || 0;
            const booked = t.bookedFlats    || 0;

            const soldPct   = total > 0 ? Math.round((sold   / total) * 100) : 0;
            const availPct  = total > 0 ? Math.round((avail  / total) * 100) : 0;
            const holdPct   = total > 0 ? Math.round((hold   / total) * 100) : 0;
            const bookedPct = total > 0 ? Math.round((booked / total) * 100) : 0;

            return {
                towerId:              t.towerId,
                towerIdProgress:      t.towerId + '_p',
                towerName:            t.towerName,
                totalFlats:           total,
                soldFlats:            sold,
                availableFlats:       avail,
                holdFlats:            hold,
                bookedFlats:          booked,
                // String versions for lightning-badge label (must be string)
                totalFlatsStr:        String(total),
                soldFlatsStr:         String(sold),
                availableFlatsStr:    String(avail),
                holdFlatsStr:         String(hold),
                bookedFlatsStr:       String(booked),
                soldPct:              soldPct,
                soldPctStyle:         `width: ${soldPct}%`,
                // Stacked bar segments
                soldStackStyle:       `width: ${soldPct}%`,
                bookedStackStyle:     `width: ${bookedPct}%`,
                holdStackStyle:       `width: ${holdPct}%`,
                availableStackStyle:  `width: ${availPct}%`
            };
        });
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  COMPUTED PROPERTIES – Bar chart data
    // ─────────────────────────────────────────────────────────────────────────

    get hasTowerData() {
        return this.towerInventory && this.towerInventory.length > 0;
    }

    get chartData() {
        const towers = this.towerInventory || [];
        if (towers.length === 0) return [];

        // Find max value across all towers for proportional scaling
        const maxVal = towers.reduce((max, t) => {
            return Math.max(max, t.soldFlats || 0, t.availableFlats || 0, t.holdFlats || 0, t.bookedFlats || 0);
        }, 1);

        return towers.map(t => {
            const soldH   = Math.round(((t.soldFlats      || 0) / maxVal) * BAR_MAX_HEIGHT);
            const availH  = Math.round(((t.availableFlats || 0) / maxVal) * BAR_MAX_HEIGHT);
            const holdH   = Math.round(((t.holdFlats      || 0) / maxVal) * BAR_MAX_HEIGHT);
            const bookedH = Math.round(((t.bookedFlats    || 0) / maxVal) * BAR_MAX_HEIGHT);

            // Truncate tower name for X-axis label
            const name = t.towerName || '';
            const shortName = name.length > 8 ? name.substring(0, 7) + '…' : name;

            return {
                towerId:        t.towerId,
                towerName:      name,
                shortName:      shortName,
                soldStyle:      `height: ${soldH}px`,
                availableStyle: `height: ${availH}px`,
                holdStyle:      `height: ${holdH}px`,
                bookedStyle:    `height: ${bookedH}px`,
                soldTitle:      `Sold: ${t.soldFlats || 0}`,
                availableTitle: `Available: ${t.availableFlats || 0}`,
                holdTitle:      `Hold: ${t.holdFlats || 0}`,
                bookedTitle:    `Booked: ${t.bookedFlats || 0}`
            };
        });
    }

    get yAxisLabels() {
        const towers = this.towerInventory || [];
        if (towers.length === 0) return [];

        const maxVal = towers.reduce((max, t) => {
            return Math.max(max, t.soldFlats || 0, t.availableFlats || 0, t.holdFlats || 0, t.bookedFlats || 0);
        }, 0);

        // Generate 5 evenly-spaced labels from maxVal down to 0
        const step = Math.ceil(maxVal / 4) || 1;
        const labels = [];
        for (let i = 4; i >= 0; i--) {
            labels.push(i * step);
        }
        return labels;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  UTILITIES
    // ─────────────────────────────────────────────────────────────────────────

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    extractErrorMessage(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        if (error && error.message) {
            return error.message;
        }
        return 'An unexpected error occurred. Please try again.';
    }
}