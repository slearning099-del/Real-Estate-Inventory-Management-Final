import { LightningElement, track } from 'lwc';
import getProjects from '@salesforce/apex/TowerUnitViewerController.getProjects';
import getPhases from '@salesforce/apex/TowerUnitViewerController.getPhases';
import getTowersByPhase from '@salesforce/apex/TowerUnitViewerController.getTowersByPhase';
import getPropertyUnits from '@salesforce/apex/TowerUnitViewerController.getPropertyUnits';
import getSubUnits from '@salesforce/apex/TowerUnitViewerController.getSubUnits';

// ── Helpers ──────────────────────────────────────────────────────────────────

const STATUS_AVAILABLE = 'Available';
const STATUS_BOOKED    = 'Booked';
const STATUS_SOLD      = 'Sold';

function formatCurrency(value) {
    if (value == null) return '—';
    return '₹' + Number(value).toLocaleString('en-IN');
}

function statusAccentClass(status) {
    if (!status) return 'unit-card-accent accent-default';
    const s = status.toLowerCase();
    if (s === 'available') return 'unit-card-accent accent-available';
    if (s === 'booked')    return 'unit-card-accent accent-booked';
    if (s === 'sold')      return 'unit-card-accent accent-sold';
    return 'unit-card-accent accent-default';
}

function statusBadgeClass(status) {
    if (!status) return 'status-badge badge-default';
    const s = status.toLowerCase();
    if (s === 'available') return 'status-badge badge-available';
    if (s === 'booked')    return 'status-badge badge-booked';
    if (s === 'sold')      return 'status-badge badge-sold';
    return 'status-badge badge-default';
}

function enrichUnit(unit) {
    return {
        ...unit,
        accentClass:          statusAccentClass(unit.Property_Unit_Status__c),
        badgeClass:           statusBadgeClass(unit.Property_Unit_Status__c),
        formattedBasePrice:   formatCurrency(unit.Base_Price__c),
        formattedFinalAmount: formatCurrency(unit.Final_Amount__c),
        floorLabel:           unit.Floor_Number__c ? `Floor ${unit.Floor_Number__c}` : '',
        subUnits:             unit.subUnits || [],
        hasSubUnits:          (unit.subUnits || []).length > 0
    };
}

// ── Component ─────────────────────────────────────────────────────────────────

export default class TowerUnitViewer extends LightningElement {
    // Hierarchy data
    @track projects = [];
    @track phases   = [];
    @track towers   = [];

    // Selections
    @track selectedProjectId = '';
    @track selectedPhaseId   = '';
    @track selectedTowerId   = '';

    // Units
    @track propertyUnits = [];

    // UI state
    @track loading   = false;
    @track showUnits = false;
    @track noData    = false;

    connectedCallback() {
        this.loadProjects();
    }

    // ── Loaders ──────────────────────────────────────────────────────────────

    loadProjects() {
        this.loading = true;
        getProjects()
            .then(result => {
                this.projects = result;
                this.loading  = false;
                this.noData   = result.length === 0;
            })
            .catch(error => {
                console.error('Error loading projects:', error);
                this.loading = false;
                this.noData  = true;
            });
    }

    loadPhases(projectId) {
        if (!projectId) { this.phases = []; return; }
        this.loading = true;
        getPhases({ projectId })
            .then(result => { this.phases = result; this.loading = false; })
            .catch(error => { console.error('Error loading phases:', error); this.loading = false; });
    }

    loadTowers(phaseId) {
        if (!phaseId) { this.towers = []; return; }
        this.loading = true;
        getTowersByPhase({ phaseId })
            .then(result => { this.towers = result; this.loading = false; })
            .catch(error => { console.error('Error loading towers:', error); this.loading = false; });
    }

    loadPropertyUnits(towerId) {
        if (!towerId) { this.propertyUnits = []; this.showUnits = false; return; }
        this.loading = true;
        getPropertyUnits({ towerId })
            .then(result => {
                const units = result.map(u => enrichUnit({ ...u, subUnits: [] }));
                this.propertyUnits = units;
                this.loading       = false;
                this.showUnits     = units.length > 0;
                this.noData        = units.length === 0;
                this.fetchSubUnitsForUnits(units);
            })
            .catch(error => {
                console.error('Error loading property units:', error);
                this.loading = false;
                this.noData  = true;
            });
    }

    fetchSubUnitsForUnits(units) {
        units.forEach(unit => this.fetchSubUnitsForUnit(unit));
    }

    fetchSubUnitsForUnit(unit) {
        getSubUnits({ propertyUnitId: unit.Id })
            .then(result => {
                this.propertyUnits = this.propertyUnits.map(u =>
                    u.Id === unit.Id ? enrichUnit({ ...u, subUnits: result }) : u
                );
            })
            .catch(error => {
                console.error('Error loading sub-units for unit ' + unit.Id, error);
            });
    }

    // ── Combobox options ──────────────────────────────────────────────────────

    get projectOptions() { return this.projects.map(p  => ({ label: p.Name,  value: p.Id  })); }
    get phaseOptions()   { return this.phases.map(ph   => ({ label: ph.Name, value: ph.Id })); }
    get towerOptions()   { return this.towers.map(t    => ({ label: t.Name,  value: t.Id  })); }

    // ── Disabled state ────────────────────────────────────────────────────────

    get isPhaseDisabled() { return !this.selectedProjectId; }
    get isTowerDisabled() { return !this.selectedPhaseId;   }

    // ── Stats ─────────────────────────────────────────────────────────────────

    get totalUnits()     { return this.propertyUnits.length; }
    get totalUnitsLabel(){ return String(this.totalUnits);   }

    get availableUnits() {
        return this.propertyUnits.filter(u =>
            (u.Property_Unit_Status__c || '').toLowerCase() === STATUS_AVAILABLE.toLowerCase()
        ).length;
    }

    get bookedUnits() {
        return this.propertyUnits.filter(u =>
            (u.Property_Unit_Status__c || '').toLowerCase() === STATUS_BOOKED.toLowerCase()
        ).length;
    }

    get soldUnits() {
        return this.propertyUnits.filter(u =>
            (u.Property_Unit_Status__c || '').toLowerCase() === STATUS_SOLD.toLowerCase()
        ).length;
    }

    // ── Empty state ───────────────────────────────────────────────────────────

    get showEmptyState() { return !this.loading && !this.showUnits; }

    get emptyStateTitle() {
        if (!this.selectedProjectId) return 'Select a Project to get started';
        if (!this.selectedPhaseId)   return 'Now select a Phase';
        if (!this.selectedTowerId)   return 'Finally, select a Tower';
        return 'No units found for this tower';
    }

    get emptyStateSubtitle() {
        if (!this.selectedProjectId) return 'Use the filters above to drill down into available units.';
        if (!this.selectedPhaseId)   return 'Choose the project phase from the dropdown above.';
        if (!this.selectedTowerId)   return 'Choose the tower to view its property units.';
        return 'Try selecting a different tower or check back later.';
    }

    // ── Handlers ──────────────────────────────────────────────────────────────

    handleProjectChange(event) {
        this.selectedProjectId = event.detail.value;
        this.selectedPhaseId   = '';
        this.selectedTowerId   = '';
        this.phases            = [];
        this.towers            = [];
        this.propertyUnits     = [];
        this.showUnits         = false;
        this.loadPhases(this.selectedProjectId);
    }

    handlePhaseChange(event) {
        this.selectedPhaseId = event.detail.value;
        this.selectedTowerId = '';
        this.towers          = [];
        this.propertyUnits   = [];
        this.showUnits       = false;
        this.loadTowers(this.selectedPhaseId);
    }

    handleTowerChange(event) {
        this.selectedTowerId = event.detail.value;
        this.showUnits       = false;
        if (this.selectedTowerId) {
            this.loadPropertyUnits(this.selectedTowerId);
        } else {
            this.propertyUnits = [];
        }
    }
}
