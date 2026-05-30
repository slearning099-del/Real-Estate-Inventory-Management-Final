# Inventory Approval Dashboard

A professional Salesforce Lightning Web Component (LWC) solution for Purchase Order inventory approval and stock management.

## 🎯 Overview

This solution provides a comprehensive dashboard for Project Managers to review, approve, and reject Purchase Order inventory items. Upon approval, items are automatically transferred into Available Item Stock and linked with Project Phases.

## ✨ Key Features

### 📊 Dashboard Components
- **Real-time KPI Cards** - Pending approvals, new requests, alerts, total value
- **Interactive Charts** - Category distribution, status breakdown, quantity analysis
- **Project Phase Tracking** - Visual allocation cards by phase
- **Searchable Data Table** - All pending items with full details
- **Bulk Operations** - Approve/reject multiple items at once

### 🔄 Approval Workflow
- **Approve Items** → Creates Available_Item_Stock__c records
- **Reject Items** → Updates status only (no stock created)
- **Remarks Support** - Add approval/rejection comments
- **Transaction Safety** - Rollback on errors

### 📈 Analytics & Insights
- **Category Distribution** (Pie Chart)
- **Approval Status** (Doughnut Chart)
- **Quantity by Type** (Bar Chart)
- **Phase Allocations** (Summary Cards)
- **High Quantity Alerts** (Items > 100)
- **New Requests Tracking** (Last 7 days)

### 🎨 UI/UX Excellence
- **Native Salesforce Design** - SLDS compliant
- **Responsive Layout** - Desktop, tablet, mobile
- **Color Coding** - Green (Approved), Red (Rejected), Yellow (Pending)
- **Loading States** - Spinners and progress indicators
- **Toast Notifications** - Success/error messages
- **Empty States** - Friendly "no data" messages
- **Auto-refresh** - Updates every 60 seconds

## 🏗️ Architecture

### Components

```
├── Apex Classes
│   ├── InventoryApprovalController.cls
│   └── InventoryApprovalControllerTest.cls
│
└── Lightning Web Components
    └── inventoryApprovalDashboard
        ├── inventoryApprovalDashboard.js
        ├── inventoryApprovalDashboard.html
        ├── inventoryApprovalDashboard.css
        └── inventoryApprovalDashboard.js-meta.xml
```

### Data Model

```
Purchase_Order__c
    ↓
Purchase_Order_Line_Item__c
    ↓ (Approval)
Available_Item_Stock__c ← Project_Phase__c
```

## 🚀 Quick Start

### Prerequisites
- Salesforce org with Lightning Experience enabled
- Custom objects configured (see DEPLOYMENT_GUIDE.md)
- Chart.js static resource uploaded

### Installation

1. **Clone or download this repository**
```bash
git clone <repository-url>
cd InventoryUi
```

2. **Deploy to Salesforce**
```bash
sf org login web --alias myOrg
sf project deploy start --source-dir force-app/main/default
```

3. **Upload Chart.js**
   - Download from https://www.chartjs.org/
   - Upload as Static Resource named `chartjs`

4. **Add to Lightning Page**
   - Use Lightning App Builder
   - Drag `inventoryApprovalDashboard` component
   - Save and activate

5. **Assign Permissions**
   - Grant access to Apex classes
   - Ensure FLS on all fields
   - Add to user profiles

## 📖 Usage

### For Project Managers

1. **View Dashboard**
   - Navigate to the Inventory Approvals page/tab
   - Review pending items and metrics

2. **Approve Items**
   - Select items from the table
   - Click **Approve** button
   - Add optional remarks
   - Confirm approval
   - ✅ Stock records created automatically

3. **Reject Items**
   - Select items from the table
   - Click **Reject** button
   - Add required remarks
   - Confirm rejection
   - ❌ Status updated (no stock created)

4. **Monitor Progress**
   - View real-time charts
   - Check phase allocations
   - Track approval metrics

## 🔧 Technical Details

### Apex Controller Methods

| Method | Purpose | Cacheable |
|--------|---------|-----------|
| `getDashboardData()` | Fetch all dashboard data | Yes |
| `approveItems()` | Approve selected items | No |
| `rejectItems()` | Reject selected items | No |
| `refreshMetrics()` | Get updated metrics | No |

### LWC Properties

| Property | Type | Description |
|----------|------|-------------|
| `dashboardData` | Object | Complete dashboard data |
| `selectedItemIds` | Array | Selected item IDs |
| `isLoading` | Boolean | Loading state |
| `chartjsInitialized` | Boolean | Chart.js loaded |

### Governor Limits Compliance

- ✅ Bulkified operations
- ✅ SOQL query optimization
- ✅ Aggregate queries for metrics
- ✅ 500 record limit per query
- ✅ Transaction savepoints

## 🧪 Testing

### Run Apex Tests
```bash
sf apex run test --class-names InventoryApprovalControllerTest --result-format human --code-coverage
```

### Test Coverage
- **Target:** >75%
- **Current:** ~85%
- **Tests:** 8 test methods
- **Scenarios:** Approval, rejection, bulk operations, error handling

## 📋 Required Fields

### Purchase_Order_Line_Item__c
- `Item_Name__c`, `Item_Code__c`, `Quantity__c`, `Unit__c`
- `Category__c`, `Approval_Status__c` (Pending/Approved/Rejected)
- `Unit_Price__c`, `Total_Amount__c`
- `Approved_Date__c`, `Approval_Remarks__c`
- `Rejected_Date__c`, `Rejection_Remarks__c`

### Available_Item_Stock__c
- `Item_Name__c`, `Item_Code__c`, `Quantity__c`, `Unit__c`
- `Category__c`, `Status__c` (Available/Allocated/Used)
- `Project_Phase__c` (Lookup)
- `Purchase_Order__c`, `Purchase_Order_Line_Item__c` (Lookups)
- `Unit_Price__c`, `Total_Value__c`

## 📚 Documentation

- [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) - Complete deployment instructions
- [Code Comments](./force-app/main/default/classes/) - Inline documentation

## 🎨 Screenshots

### Dashboard Overview
![Dashboard](https://via.placeholder.com/800x400?text=Dashboard+Overview)

### Approval Modal
![Approval](https://via.placeholder.com/800x400?text=Approval+Modal)

### Charts & Analytics
![Charts](https://via.placeholder.com/800x400?text=Charts+Analytics)

## 🐛 Troubleshooting

### Charts Not Displaying
- Verify Chart.js static resource uploaded
- Check browser console for errors
- Clear browser cache

### Apex Errors
- Ensure test data exists
- Check field permissions
- Review debug logs

### Permission Issues
- Verify FLS on all fields
- Check CRUD permissions
- Validate Apex class access

## 🤝 Contributing

This is a production-ready solution. For customizations:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📝 License

This project is provided as-is for use in Salesforce implementations.

## 👥 Authors

Salesforce Development Team - 2026

## 🆘 Support

For issues or questions:
1. Review DEPLOYMENT_GUIDE.md
2. Check debug logs
3. Run test classes
4. Review code comments

## 🎯 Roadmap

- [ ] Email notifications on approval/rejection
- [ ] Export to Excel functionality
- [ ] Advanced filtering options
- [ ] Approval history timeline
- [ ] Mobile app support
- [ ] Integration with Salesforce Flow

---

**Built with ❤️ using Salesforce Lightning Web Components**