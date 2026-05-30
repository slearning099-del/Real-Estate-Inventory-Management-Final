import{ LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDashboardDataByRecordId from '@salesforce/apex/POApprovalDashboardController.getDashboardDataByRecordId';
import submitForApproval          from '@salesforce/apex/POApprovalDashboardController.submitForApproval';
import approveOrder               from '@salesforce/apex/POApprovalDashboardController.approveOrder';
import rejectOrder                from '@salesforce/apex/POApprovalDashboardController.rejectOrder';

// Chart.js CDN
const CHARTJS_URL = 'https://cdnjs.cloudflare.com/ajax/libs/Chart.js/3.9.1/chart.min.js';

const STATUS_CLASS_MAP = {
    'Draft'            : 'badge badge-draft',
    'Pending Approval' : 'badge badge-pending',
    'Approved'         : 'badge badge-approved',
    'Rejected'         : 'badge badge-rejected',
    'Received'         : 'badge badge-received',
    'Canceled'         : 'badge badge-canceled'
};

export default class PoApprovalDashboard extends LightningElement {

    /** Injected by platform — PO record page gives Purchase_Order__c Id */
    @api recordId;

    @track data           = null;
    @track isLoading      = true;
    @track isProcessing   = false;
    @track isSubmitting   = false;
    @track hasError       = false;
    @track errorMessage   = '';
    @track remarks        = '';
    @track submitRemarks  = '';

    _chartJsLoaded = false;
    _charts        = {};
    _chartsDrawn   = false;

    // ── Required by lightning__RecordAction ──────────────────────
    @api invoke() {
        this._chartsDrawn = false;
        this._destroyCharts();
        this._loadData();
    }

    // ── Lifecycle ────────────────────────────────────────────────
    connectedCallback() {
        this._loadData();
    }

    renderedCallback() {
        if (this.data && !this.isLoading && !this._chartsDrawn) {
            this._chartsDrawn = true;
            this._renderCharts();
        }
    }

    // ── Computed properties ──────────────────────────────────────
    get showDashboard() {
        return !this.isLoading && !this.hasError && this.data != null;
    }

    get hasLineItems() {
        return this.data && this.data.lineItems && this.data.lineItems.length > 0;
    }

    get hasHistory() {
        return this.data &&
               this.data.approvalSummary &&
               this.data.approvalSummary.history &&
               this.data.approvalSummary.history.length > 0;
    }

    get lineItemCountLabel() {
        const count = this.data && this.data.lineItems ? this.data.lineItems.length : 0;
        return `${count} Item${count !== 1 ? 's' : ''}`;
    }

    get statusBadgeClass() {
        const status = this.data && this.data.poHeader ? this.data.poHeader.status : '';
        return STATUS_CLASS_MAP[status] || 'badge badge-draft';
    }

    get formattedTotalCost() {
        const cost = this.data && this.data.poHeader ? this.data.poHeader.totalCost : 0;
        return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(cost || 0);
    }

    /** Show "Submit for Approval" panel only when PO is in Draft */
    get showSubmitForApproval() {
        return this.data && this.data.canSubmitForApproval === true;
    }

    get submitButtonDisabled() {
        return this.isSubmitting || this.isProcessing;
    }

    get approveRejectDisabled() {
        return this.isProcessing || this.isSubmitting;
    }


    // ── Event handlers ───────────────────────────────────────────

    handleSubmitRemarksChange(event) {
        this.submitRemarks = event.detail.value;
    }

    handleRemarksChange(event) {
        this.remarks = event.detail.value;
    }

    handleRefresh() {
        this._destroyCharts();
        this._chartsDrawn = false;
        this._loadData();
    }

    /**
     * Submit for Approval
     * Calls Apex → submits PO to approval process → Apex sends bell
     * notification to approver with direct PO record link.
     */
    async handleSubmitForApproval() {
        const confirmed = await this._confirm(
            'Submit for Approval',
            `Submit "${this.data.poHeader.poNumber}" for approval?\n\n` +
            `A bell notification will be sent to the approver with a direct link to this record.`
        );
        if (!confirmed) return;

        this.isSubmitting = true;
        try {
            const result = await submitForApproval({
                poRecordId : this.recordId,
                comments   : this.submitRemarks || 'Submitted for approval via PO Dashboard.'
            });
            if (result.success) {
                this._toast('Submitted for Approval', result.message, 'success');
                this.submitRemarks = '';
                this._destroyCharts();
                this._chartsDrawn = false;
                await this._loadData();
            } else {
                this._toast('Submission Failed', result.message, 'error');
            }
        } catch (err) {
            this._toast('Error', this._extractError(err), 'error');
        } finally {
            this.isSubmitting = false;
        }
    }

    async handleApprove() {
        if (!this.data || !this.data.workItemId) {
            this._toast('No work item', 'No pending approval work item found.', 'warning');
            return;
        }
        const confirmed = await this._confirm(
            'Approve Purchase Order',
            `Are you sure you want to APPROVE "${this.data.poHeader.poNumber}"? ` +
            `This will create ${this.data.poHeader.totalItems} Available Stock record(s).`
        );
        if (!confirmed) return;

        this.isProcessing = true;
        try {
            const result = await approveOrder({
                workItemId : this.data.workItemId,
                comments   : this.remarks || 'Approved via PO Approval Dashboard.'
            });
            if (result.success) {
                this._toast('Approved', result.message, 'success');
                this._destroyCharts();
                this._chartsDrawn = false;
                await this._loadData();
            } else {
                this._toast('Approval Failed', result.message, 'error');
            }
        } catch (err) {
            this._toast('Error', this._extractError(err), 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    async handleReject() {
        if (!this.data || !this.data.workItemId) {
            this._toast('No work item', 'No pending approval work item found.', 'warning');
            return;
        }
        if (!this.remarks || this.remarks.trim() === '') {
            this._toast('Remarks Required', 'Please add a reason before rejecting.', 'warning');
            return;
        }
        const confirmed = await this._confirm(
            'Reject Purchase Order',
            `Are you sure you want to REJECT "${this.data.poHeader.poNumber}"?`
        );
        if (!confirmed) return;

        this.isProcessing = true;
        try {
            const result = await rejectOrder({
                workItemId : this.data.workItemId,
                comments   : this.remarks
            });
            if (result.success) {
                this._toast('Rejected', result.message, 'info');
                this._destroyCharts();
                this._chartsDrawn = false;
                await this._loadData();
            } else {
                this._toast('Rejection Failed', result.message, 'error');
            }
        } catch (err) {
            this._toast('Error', this._extractError(err), 'error');
        } finally {
            this.isProcessing = false;
        }
    }


    // ── Data loading ─────────────────────────────────────────────

    async _loadData() {
        if (!this.recordId) {
            this.hasError     = true;
            this.errorMessage = 'No record ID provided.';
            this.isLoading    = false;
            return;
        }
        this.isLoading    = true;
        this.hasError     = false;
        this._chartsDrawn = false;
        try {
            const raw = await getDashboardDataByRecordId({ recordId: this.recordId });
            if (raw && raw.lineItems) {
                raw.lineItems = raw.lineItems.map((item, idx) => ({
                    ...item,
                    rowIndex : idx + 1
                }));
            }
            this.data = raw;
        } catch (err) {
            this.hasError     = true;
            this.errorMessage = this._extractError(err);
            this.data         = null;
        } finally {
            this.isLoading = false;
        }
    }

    // ── Chart rendering ──────────────────────────────────────────

    async _renderCharts() {
        if (!this.data) return;
        try {
            await this._loadChartJs();
            this._destroyCharts();
            this._drawPieChart('.categoryPieChart', this.data.categoryChart || [], 'Item Category Distribution');
            this._drawPieChart('.statusPieChart',   this.data.statusChart   || [], 'Approval Status');
            this._drawBarChart('.quantityBarChart', this.data.quantityChart || [], 'Quantity by Item');
        } catch (e) {
            console.warn('[poApprovalDashboard] Chart render error:', e);
        }
    }

    _loadChartJs() {
        if (this._chartJsLoaded && window.Chart) return Promise.resolve();
        return new Promise((resolve, reject) => {
            if (window.Chart) { this._chartJsLoaded = true; resolve(); return; }
            const script   = document.createElement('script');
            script.src     = CHARTJS_URL;
            script.onload  = () => { this._chartJsLoaded = true; resolve(); };
            script.onerror = () => reject(new Error('Chart.js failed to load'));
            document.head.appendChild(script);
        });
    }

    _drawPieChart(selector, entries, title) {
        const canvas = this.template.querySelector(selector);
        if (!canvas || !entries || entries.length === 0) return;
        this._charts[selector] = new window.Chart(canvas, {
            type : 'pie',
            data : {
                labels   : entries.map(e => e.label),
                datasets : [{
                    label           : title,
                    data            : entries.map(e => Number(e.value || 0)),
                    backgroundColor : entries.map(e => e.color),
                    borderColor     : '#ffffff',
                    borderWidth     : 2
                }]
            },
            options : {
                responsive : true, maintainAspectRatio : true,
                plugins : {
                    legend  : { position: 'bottom', labels: { font: { size: 11 }, padding: 12 } },
                    tooltip : { callbacks: { label: ctx => ` ${ctx.label}: ${ctx.parsed}` } }
                }
            }
        });
    }

    _drawBarChart(selector, entries, title) {
        const canvas = this.template.querySelector(selector);
        if (!canvas || !entries || entries.length === 0) return;
        this._charts[selector] = new window.Chart(canvas, {
            type : 'bar',
            data : {
                labels   : entries.map(e => e.label),
                datasets : [{
                    label           : title,
                    data            : entries.map(e => Number(e.value || 0)),
                    backgroundColor : entries.map(e => e.color),
                    borderRadius    : 4
                }]
            },
            options : {
                responsive : true, maintainAspectRatio : true,
                plugins : { legend: { display: false } },
                scales  : {
                    x : { ticks: { autoSkip: false, maxRotation: 45, minRotation: 0, font: { size: 10 } } },
                    y : { beginAtZero: true, ticks: { font: { size: 10 } } }
                }
            }
        });
    }

    _destroyCharts() {
        Object.values(this._charts).forEach(c => { if (c && typeof c.destroy === 'function') c.destroy(); });
        this._charts = {};
    }

    // ── Helpers ──────────────────────────────────────────────────

    _toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _extractError(err) {
        if (!err) return 'An unknown error occurred.';
        if (err.body && err.body.message) return err.body.message;
        if (err.message) return err.message;
        return JSON.stringify(err);
    }

    _confirm(title, message) {
        // eslint-disable-next-line no-alert
        return Promise.resolve(window.confirm(`${title}\n\n${message}`));
    }
}
