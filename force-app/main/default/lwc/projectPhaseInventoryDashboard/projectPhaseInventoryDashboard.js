import { LightningElement, track, wire } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getProjects from '@salesforce/apex/ProjectPhaseInventoryController.getProjects';
import getDashboardData from '@salesforce/apex/ProjectPhaseInventoryController.getDashboardData';
import CHARTJS from '@salesforce/resourceUrl/ChartJs';

const COLUMNS = [
    { label: 'Phase Name', fieldName: 'phaseName', type: 'text', sortable: true },
    { label: 'Item Name', fieldName: 'itemName', type: 'text', sortable: true },
    { label: 'Available Quantity', fieldName: 'availableQty', type: 'number', cellAttributes: { alignment: 'left' } },
    { label: 'Used Quantity', fieldName: 'usedQty', type: 'number', cellAttributes: { alignment: 'left' } },
    { label: 'Returned Quantity', fieldName: 'returnedQty', type: 'number', cellAttributes: { alignment: 'left' } }
];

export default class ProjectPhaseInventoryDashboard extends LightningElement {
    @track projectOptions = [];
    @track selectedProjectId = '';
    @track phaseSummaries = [];
    @track inventoryItems = [];
    @track filteredInventoryItems = [];
    @track selectedPhaseId = '';
    @track isLoading = false;
    @track chartJsInitialized = false;
    
    columns = COLUMNS;
    donutChartInstance = null;
    barChartInstance = null;
    
    // Computed properties
    get totalAvailable() {
        return this.dashboardData?.totalAvailable?.toFixed(0) || 0;
    }
    
    get totalUsed() {
        return this.dashboardData?.totalUsed?.toFixed(0) || 0;
    }
    
    get totalReturned() {
        return this.dashboardData?.totalReturned?.toFixed(0) || 0;
    }
    
    get showDashboard() {
        return !this.isLoading && this.selectedProjectId && this.dashboardData;
    }
    
    get showNoData() {
        return !this.isLoading && this.selectedProjectId && !this.dashboardData;
    }
    
    get noDataMessage() {
        if (!this.selectedProjectId) {
            return 'Please select a project to view inventory data.';
        }
        return 'No inventory data found for the selected project.';
    }
    
    get tableTitle() {
        if (this.selectedPhaseId) {
            const phase = this.phaseSummaries.find(p => p.phaseId === this.selectedPhaseId);
            return phase ? `Inventory Details - ${phase.phaseName}` : 'Inventory Details';
        }
        return 'All Inventory Details';
    }
    
    dashboardData = null;
    
    // Wire Projects
    @wire(getProjects)
    wiredProjects({ error, data }) {
        if (data) {
            this.projectOptions = data.map(project => ({
                label: project.name,
                value: project.id
            }));
        } else if (error) {
            this.showErrorToast('Error loading projects', error.body?.message || 'Unknown error');
        }
    }
    
    // Lifecycle Hooks
    connectedCallback() {
        this.loadChartJs();
    }
    
    renderedCallback() {
        if (this.chartJsInitialized && this.dashboardData) {
            this.updateCharts();
        }
    }
    
    // Load Chart.js
    loadChartJs() {
        if (this.chartJsInitialized) {
            return;
        }
        
        loadScript(this, CHARTJS)
            .then(() => {
                this.chartJsInitialized = true;
                if (this.dashboardData) {
                    this.updateCharts();
                }
            })
            .catch(error => {
                this.showErrorToast('Error loading Chart.js', error.message);
            });
    }
    
    // Handle Project Change
    handleProjectChange(event) {
        this.selectedProjectId = event.detail.value;
        this.selectedPhaseId = '';
        this.loadDashboardData();
    }
    
    // Handle Phase Click
    handlePhaseClick(event) {
        this.selectedPhaseId = event.currentTarget.dataset.phaseId;
        this.filterInventoryItems();
        this.updateBarChart();
    }
    
    // Handle Show All
    handleShowAll() {
        this.selectedPhaseId = '';
        this.filterInventoryItems();
        this.destroyBarChart();
    }
    
    // Load Dashboard Data
    loadDashboardData() {
        if (!this.selectedProjectId) {
            return;
        }
        
        this.isLoading = true;
        this.dashboardData = null;
        
        getDashboardData({ projectId: this.selectedProjectId })
            .then(data => {
                this.dashboardData = data;
                this.phaseSummaries = data.phaseSummaries || [];
                this.inventoryItems = data.inventoryItems || [];
                this.filterInventoryItems();
                
                if (this.chartJsInitialized) {
                    this.updateCharts();
                }
            })
            .catch(error => {
                this.showErrorToast('Error loading dashboard data', error.body?.message || 'Unknown error');
                this.dashboardData = null;
            })
            .finally(() => {
                this.isLoading = false;
            });
    }
    
    // Filter Inventory Items
    filterInventoryItems() {
        if (this.selectedPhaseId) {
            this.filteredInventoryItems = this.inventoryItems.filter(
                item => item.phaseId === this.selectedPhaseId
            );
        } else {
            this.filteredInventoryItems = [...this.inventoryItems];
        }
    }
    
    // Update Charts
    updateCharts() {
        this.updateDonutChart();
        if (this.selectedPhaseId) {
            this.updateBarChart();
        } else {
            this.destroyBarChart();
        }
    }
    
    // Update Donut Chart
    updateDonutChart() {
        const canvas = this.template.querySelector('canvas[lwc\\:ref="donutChart"]');
        if (!canvas || !this.dashboardData) {
            return;
        }
        
        const ctx = canvas.getContext('2d');
        
        if (this.donutChartInstance) {
            this.donutChartInstance.destroy();
        }
        
        const chartData = {
            labels: ['Available Stock', 'Used Stock', 'Returned Stock'],
            datasets: [{
                data: [
                    this.dashboardData.totalAvailable || 0,
                    this.dashboardData.totalUsed || 0,
                    this.dashboardData.totalReturned || 0
                ],
                backgroundColor: [
                    '#34A853',
                    '#EA4335',
                    '#FBBC04'
                ],
                borderWidth: 0
            }]
        };
        
        this.donutChartInstance = new window.Chart(ctx, {
            type: 'doughnut',
            data: chartData,
            options: {
                responsive: true,
                maintainAspectRatio: true,
                plugins: {
                    legend: {
                        position: 'bottom',
                        labels: {
                            padding: 15,
                            font: {
                                size: 12
                            }
                        }
                    },
                    tooltip: {
                        callbacks: {
                            label: function(context) {
                                return context.label + ': ' + context.parsed.toFixed(0) + ' units';
                            }
                        }
                    }
                }
            }
        });
    }
    
    // Update Bar Chart
    updateBarChart() {
        const canvas = this.template.querySelector('canvas[lwc\\:ref="barChart"]');
        if (!canvas || !this.selectedPhaseId) {
            return;
        }
        
        const ctx = canvas.getContext('2d');
        
        if (this.barChartInstance) {
            this.barChartInstance.destroy();
        }
        
        const phaseItems = this.inventoryItems.filter(
            item => item.phaseId === this.selectedPhaseId
        );
        
        const labels = phaseItems.map(item => item.itemName);
        const availableData = phaseItems.map(item => item.availableQty || 0);
        const usedData = phaseItems.map(item => item.usedQty || 0);
        const returnedData = phaseItems.map(item => item.returnedQty || 0);
        
        const chartData = {
            labels: labels,
            datasets: [
                {
                    label: 'Available',
                    data: availableData,
                    backgroundColor: '#34A853',
                    borderWidth: 0
                },
                {
                    label: 'Used',
                    data: usedData,
                    backgroundColor: '#EA4335',
                    borderWidth: 0
                },
                {
                    label: 'Returned',
                    data: returnedData,
                    backgroundColor: '#FBBC04',
                    borderWidth: 0
                }
            ]
        };
        
        this.barChartInstance = new window.Chart(ctx, {
            type: 'bar',
            data: chartData,
            options: {
                responsive: true,
                maintainAspectRatio: true,
                scales: {
                    y: {
                        beginAtZero: true,
                        ticks: {
                            stepSize: 1
                        }
                    }
                },
                plugins: {
                    legend: {
                        position: 'top',
                        labels: {
                            padding: 15,
                            font: {
                                size: 12
                            }
                        }
                    },
                    tooltip: {
                        callbacks: {
                            label: function(context) {
                                return context.dataset.label + ': ' + context.parsed.y.toFixed(0) + ' units';
                            }
                        }
                    }
                }
            }
        });
    }
    
    // Destroy Bar Chart
    destroyBarChart() {
        if (this.barChartInstance) {
            this.barChartInstance.destroy();
            this.barChartInstance = null;
        }
    }
    
    // Show Error Toast
    showErrorToast(title, message) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: 'error',
            mode: 'sticky'
        });
        this.dispatchEvent(event);
    }
}