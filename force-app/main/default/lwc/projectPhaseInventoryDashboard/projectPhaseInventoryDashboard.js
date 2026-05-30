import { LightningElement, api } from 'lwc';
import getInventoryDashboardData from '@salesforce/apex/ProjectPhaseInventoryDashboardController.getInventoryDashboardData';

const STATUS_OPTIONS = [
  { label: 'All', value: 'All' },
  { label: 'Available', value: 'Available' },
  { label: 'Used', value: 'Used' },
  { label: 'Returned', value: 'Returned' }
];

export default class ProjectPhaseInventoryDashboard extends LightningElement {
  @api recordId;

  isLoading = true;
  startDate;
  endDate;
  itemCategory = 'All';
  stockStatus = 'All';
  refreshTimer;

  summary = {
    totalAvailable: 0,
    totalUsed: 0,
    totalReturned: 0,
    remainingStock: 0,
    usagePercentage: 0,
    inventoryHealth: 'Healthy'
  };

  itemSummaries = [];

  columns = [
    { label: 'Item Name', fieldName: 'itemName', type: 'text' },
    { label: 'Item Code', fieldName: 'itemCode', type: 'text' },
    { label: 'Unit', fieldName: 'unit', type: 'text' },
    { label: 'Available', fieldName: 'availableQuantity', type: 'number', cellAttributes: { alignment: 'left' } },
    { label: 'Used', fieldName: 'usedQuantity', type: 'number', cellAttributes: { alignment: 'left' } },
    { label: 'Returned', fieldName: 'returnedQuantity', type: 'number', cellAttributes: { alignment: 'left' } },
    { label: 'Remaining', fieldName: 'remainingQuantity', type: 'number', cellAttributes: { alignment: 'left' } },
    { label: 'Usage %', fieldName: 'usagePercentage', type: 'number', 
      typeAttributes: { maximumFractionDigits: 1 }, cellAttributes: { alignment: 'left' } },
    { label: 'Health', fieldName: 'inventoryHealth', type: 'text' }
  ];

  categoryOptions = [{ label: 'All', value: 'All' }];
  statusOptions = STATUS_OPTIONS;

  connectedCallback() {
    this.loadData();
    this.refreshTimer = window.setInterval(() => this.loadData(), 60000);
  }

  disconnectedCallback() {
    if (this.refreshTimer) {
      window.clearInterval(this.refreshTimer);
    }
  }

  handleStartDateChange(event) {
    this.startDate = event.detail.value;
    this.loadData();
  }

  handleEndDateChange(event) {
    this.endDate = event.detail.value;
    this.loadData();
  }

  handleCategoryChange(event) {
    this.itemCategory = event.detail.value;
    this.loadData();
  }

  handleStatusChange(event) {
    this.stockStatus = event.detail.value;
    this.loadData();
  }

  handleResetFilters() {
    this.startDate = null;
    this.endDate = null;
    this.itemCategory = 'All';
    this.stockStatus = 'All';
    this.loadData();
  }

  refreshData() {
    this.loadData();
  }

  async loadData() {
    if (!this.recordId) {
      return;
    }
    this.isLoading = true;

    try {
      const response = await getInventoryDashboardData({
        projectPhaseId: this.recordId,
        startDate: this.startDate || null,
        endDate: this.endDate || null,
        itemCategory: this.itemCategory === 'All' ? null : this.itemCategory,
        stockStatus: this.stockStatus
      });

      this.summary = {
        totalAvailable: response.totalAvailable || 0,
        totalUsed: response.totalUsed || 0,
        totalReturned: response.totalReturned || 0,
        remainingStock: response.remainingStock || 0,
        usagePercentage: Number(response.usagePercentage || 0).toFixed(1),
        inventoryHealth: response.inventoryHealth || 'Healthy'
      };

      // Set the item summaries list for the data table
      this.itemSummaries = response.itemSummaries || [];

    } catch (error) {
      this.summary = {
        totalAvailable: 0,
        totalUsed: 0,
        totalReturned: 0,
        remainingStock: 0,
        usagePercentage: 0,
        inventoryHealth: 'Critical'
      };
      this.itemSummaries = [];
      // Keep console error for support triage in lower environments.
      // eslint-disable-next-line no-console
      console.error('Project phase inventory dashboard failed', error);
    } finally {
      this.isLoading = false;
    }
  }

}