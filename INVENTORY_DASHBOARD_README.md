# Project Phase Inventory Dashboard

## Overview
A professional Salesforce Lightning Web Component (LWC) dashboard for comprehensive inventory management across project phases. The dashboard provides real-time visualization of available, used, and returned stock with interactive charts and detailed data tables.

## Features

### 1. **Project Selection**
- Dropdown selector to choose from active projects
- Dynamic data loading based on project selection
- Automatic refresh when switching projects

### 2. **KPI Cards**
Three visually appealing cards displaying:
- **Total Available Stock** (Green) - Package icon
- **Total Used Stock** (Red) - Cart icon
- **Total Returned Stock** (Yellow) - Undo icon

### 3. **Interactive Donut Chart**
- Visual distribution of stock across categories
- Color-coded segments matching KPI cards
- Hover tooltips showing exact quantities
- Responsive design

### 4. **Phase Summary Section**
- Clickable phase cards showing:
  - Phase name
  - Available stock quantity
  - Used stock quantity
  - Returned stock quantity
- Hover effects for better UX
- Click to filter data by phase

### 5. **Detailed Inventory Table**
Lightning Datatable displaying:
- Phase Name
- Item Name
- Available Quantity
- Used Quantity
- Returned Quantity
- Sortable columns
- Row numbering
- Dynamic filtering based on phase selection

### 6. **Item-wise Bar Chart**
- Appears when a phase is selected
- Grouped bar chart showing all items in the selected phase
- Three data series: Available, Used, Returned
- Color-coded bars matching the theme

### 7. **Professional UI/UX**
- Lightning Design System (SLDS) compliance
- Smooth animations and transitions
- Loading spinners during data fetch
- Friendly no-data messages
- Responsive design for mobile/tablet
- Custom scrollbars
- Professional color scheme

## Technical Architecture

### Components Created

#### 1. **Apex Controller**: `ProjectPhaseInventoryController.cls`
**Methods:**
- `getProjects()` - Cacheable method to fetch active projects
- `getDashboardData(projectId)` - Fetches complete dashboard data including phases and stock

**Wrapper Classes:**
- `ProjectWrapper` - Project data structure
- `PhaseSummary` - Phase-level stock aggregation
- `InventoryItem` - Item-level stock details
- `DashboardData` - Complete dashboard response

#### 2. **LWC Component**: `projectPhaseInventoryDashboard`
**Files:**
- `projectPhaseInventoryDashboard.html` - Template with SLDS markup
- `projectPhaseInventoryDashboard.js` - Controller with Chart.js integration
- `projectPhaseInventoryDashboard.css` - Professional styling
- `projectPhaseInventoryDashboard.js-meta.xml` - Component configuration

#### 3. **Static Resource**: `ChartJs`
- Chart.js v4.4.0 library for interactive charts
- Loaded dynamically via platformResourceLoader

#### 4. **Test Class**: `ProjectPhaseInventoryControllerTest.cls`
Comprehensive test coverage including:
- Project retrieval
- Dashboard data loading
- Null handling
- Empty data scenarios
- Calculation verification
- Item aggregation

## Data Model

The dashboard works with the following Salesforce objects:

```
Project__c (with Active__c checkbox)
   ↓
Project_Phase__c (Lookup/Master-Detail to Project__c)
   ↓ (Lookup relationships)
   ├── Available_Stock__c (fields: Item_Name__c, Quantity__c)
   ├── Used_Stock__c (fields: Item_Name__c, Quantity__c)
   └── Return_Stock__c (fields: Item_Name__c, Quantity__c)
```

### Required Fields

**Project__c:**
- Name (Standard)
- Active__c (Checkbox)

**Project_Phase__c:**
- Name (Standard)
- Project__c (Lookup to Project__c)

**Available_Stock__c / Used_Stock__c / Return_Stock__c:**
- Name (Standard)
- Project_Phase__c (Lookup to Project_Phase__c)
- Item_Name__c (Text)
- Quantity__c (Number)

## Installation & Deployment

### Prerequisites
1. Salesforce org with the above custom objects
2. Salesforce CLI installed
3. VSCode with Salesforce Extensions

### Deployment Steps

#### 1. **Deploy Apex Classes**
```bash
sf project deploy start --source-dir force-app/main/default/classes/ProjectPhaseInventoryController.cls
sf project deploy start --source-dir force-app/main/default/classes/ProjectPhaseInventoryControllerTest.cls
```

#### 2. **Deploy Static Resource**
```bash
sf project deploy start --source-dir force-app/main/default/staticresources/ChartJs.js
sf project deploy start --source-dir force-app/main/default/staticresources/ChartJs.resource-meta.xml
```

#### 3. **Deploy LWC Component**
```bash
sf project deploy start --source-dir force-app/main/default/lwc/projectPhaseInventoryDashboard
```

#### 4. **Run Tests**
```bash
sf apex run test --class-names ProjectPhaseInventoryControllerTest --result-format human
```

### Quick Deployment (All at Once)
```bash
sf project deploy start --source-dir force-app/main/default
```

## Usage

### Adding to Lightning Pages

1. **App Builder:**
   - Navigate to Setup → Lightning App Builder
   - Edit or create a new Lightning Page
   - Drag "Project Phase Inventory Dashboard" component onto the page
   - Save and activate

2. **Home Page:**
   - Add to Home page for quick access
   - Configure height property (default: 800px)

3. **App Page:**
   - Add to custom app pages
   - Ideal for dedicated inventory management apps

4. **Record Page:**
   - Can be added to Project__c or Project_Phase__c record pages

### User Workflow

1. **Select a Project** from the dropdown
2. **View KPIs** in the summary cards
3. **Analyze distribution** in the donut chart
4. **Browse phase summaries** in the right panel
5. **Click a phase** to filter the inventory table
6. **View item details** in the bar chart (when phase is selected)
7. **Click "Show All Phases"** to reset filters

## Customization

### Adjusting Colors
Edit `projectPhaseInventoryDashboard.css`:
```css
.kpi-available { border-left: 4px solid #YOUR_COLOR; }
.stat-available { color: #YOUR_COLOR; }
```

### Modifying Field Mappings
Edit `ProjectPhaseInventoryController.cls` SOQL queries to match your org's field API names.

### Adding New Columns
Update `COLUMNS` constant in `projectPhaseInventoryDashboard.js`:
```javascript
const COLUMNS = [
    { label: 'Your Column', fieldName: 'yourField', type: 'text' },
    // ... existing columns
];
```

### Chart Customization
Modify chart options in `updateDonutChart()` and `updateBarChart()` methods in the JavaScript controller.

## Performance Considerations

1. **Caching:** `getProjects()` uses `@AuraEnabled(cacheable=true)` for optimal performance
2. **Bulk Processing:** Apex controller processes data in collections
3. **Lazy Loading:** Charts load only when data is available
4. **Efficient Filtering:** Client-side filtering for phase selection
5. **Pagination:** Consider adding pagination for large datasets (500+ items)

## Security

- **with sharing:** Apex controller respects org-wide sharing rules
- **FLS/CRUD:** Ensure users have read access to all custom objects
- **Permissions:** Grant permission to the component via Lightning Page assignment

## Troubleshooting

### Chart.js Not Loading
- Verify ChartJs static resource is deployed
- Check browser console for errors
- Ensure static resource name matches import statement

### No Data Displayed
- Verify Active__c checkbox is true on Project__c
- Ensure Project_Phase__c records exist
- Check stock records have Quantity__c values
- Verify lookup relationships are correctly established

### Performance Issues
- Reduce LIMIT in SOQL queries if needed
- Add indexes on lookup fields
- Consider pagination for large datasets

## Browser Compatibility

- Chrome (Recommended)
- Firefox
- Safari
- Edge
- Mobile browsers (iOS Safari, Chrome Mobile)

## Future Enhancements

Potential improvements:
1. Export to Excel/PDF functionality
2. Date range filters
3. Search functionality
4. Advanced filtering options
5. Real-time updates using Platform Events
6. Historical trend analysis
7. Predictive analytics
8. Mobile app version

## Support

For issues or questions:
1. Check Salesforce Debug Logs
2. Review browser console errors
3. Verify object permissions
4. Test with sample data

## Version History

**v1.0.0** (May 2026)
- Initial release
- Complete dashboard with charts
- Full test coverage
- Professional UI/UX

## License

Proprietary - For internal use only

## Credits

Developed using:
- Salesforce Lightning Web Components
- Chart.js v4.4.0
- Lightning Design System (SLDS)
- Salesforce Apex

---

**Built with ❤️ for Professional Inventory Management**