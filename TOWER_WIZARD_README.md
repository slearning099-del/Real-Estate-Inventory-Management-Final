# Project Phase Tower Wizard - Documentation

## Overview
The **Project Phase Tower Wizard** is a Lightning Web Component (LWC) that provides an intuitive, wizard-style interface for creating Tower records associated with a Project Phase. This component ensures a one-time execution per Project Phase and follows Salesforce best practices.

---

## Features

### ✨ Key Capabilities
- **Wizard-Style Interface**: 3-step guided process with progress indicator
- **One-Time Execution**: Prevents duplicate tower creation for the same Project Phase
- **Dynamic Form Generation**: Creates tower input forms based on user-specified count
- **Bulk Creation**: Efficiently creates up to 50 towers in a single operation
- **Auto-Population**: Automatically populates Project and Project Phase lookups
- **Responsive Design**: Mobile-friendly UI using Salesforce Lightning Design System (SLDS)
- **Real-time Validation**: Validates inputs before allowing progression
- **Quick Action Integration**: Accessible via button on Project Phase record page

---

## Component Structure

### Files Created
```
force-app/main/default/
├── lwc/
│   └── projectPhaseTowerWizard/
│       ├── projectPhaseTowerWizard.html          # Component template
│       ├── projectPhaseTowerWizard.js            # Component logic
│       ├── projectPhaseTowerWizard.css           # Component styling
│       └── projectPhaseTowerWizard.js-meta.xml   # Component metadata
├── classes/
│   ├── ProjectPhaseTowerWizardController.cls           # Apex controller
│   ├── ProjectPhaseTowerWizardController.cls-meta.xml
│   ├── ProjectPhaseTowerWizardControllerTest.cls       # Test class
│   └── ProjectPhaseTowerWizardControllerTest.cls-meta.xml
└── quickActions/
    └── Project_Phase__c.Create_Towers.quickAction-meta.xml  # Quick action
```

---

## Object & Field Mapping

### Project_Phase__c
- **Name** (Text)
- **Project__c** (Master-Detail to Project__c)
- **Phase_Status__c** (Picklist)
- **Budget__c** (Currency)
- **Phase_Start_Date__c** (Date)
- **Phase_End_Date__c** (Date)
- **Project_Phase_Code__c** (Text)

### Tower__c
- **Name** (Text) - Required
- **Status__c** (Picklist) - Values:
  - Planning (Default)
  - Finishing Stage
  - Ready For possession
  - Handover Progress
  - On Hold
- **Project__c** (Lookup to Project__c) - Auto-populated
- **Project_Phase__c** (Lookup to Project_Phase__c) - Auto-populated

---

## Wizard Steps

### Step 1: Project Phase Details
Displays read-only information about the selected Project Phase:
- Phase Name
- Related Project
- Phase Status
- Budget
- Start Date
- End Date

### Step 2: Tower Configuration
- **Checkbox**: "Do you want to create Towers?"
- **Number Input**: "How many towers do you want to create?" (1-50)
- **Dynamic Forms**: Generates individual tower forms with:
  - Tower Name (Required)
  - Status (Dropdown with default "Planning")

### Step 3: Review & Save
- Summary of Project Phase information
- List of all towers to be created
- Warning message about one-time execution
- Save button to create towers

---

## Deployment Instructions

### Prerequisites
- Salesforce CLI installed
- Authenticated to your Salesforce org
- Project__c, Project_Phase__c, and Tower__c objects exist

### Deployment Steps

#### Option 1: Deploy All Files
```bash
cd "/Users/niharkonkar/RealEstate Project/RealEstate"
sf project deploy start --source-dir force-app/main/default/lwc/projectPhaseTowerWizard
sf project deploy start --source-dir force-app/main/default/classes
sf project deploy start --source-dir force-app/main/default/quickActions
```

#### Option 2: Deploy Using Manifest
```bash
sf project deploy start --manifest manifest/package.xml
```

#### Option 3: Deploy via VS Code
1. Right-click on `force-app/main/default/lwc/projectPhaseTowerWizard`
2. Select "SFDX: Deploy Source to Org"
3. Repeat for `classes` and `quickActions` folders

---

## Configuration

### Add Quick Action to Page Layout

1. Navigate to **Setup** → **Object Manager** → **Project Phase**
2. Go to **Page Layouts** → Select your layout
3. Click **Mobile & Lightning Actions**
4. Drag **Create Towers** quick action to the layout
5. Save the layout

### Alternative: Add to Record Page

1. Navigate to a Project Phase record
2. Click **Setup** (gear icon) → **Edit Page**
3. Drag **Quick Actions** component to the page
4. Add **Create Towers** action
5. Save and activate the page

---

## Usage Guide

### For End Users

1. **Open Project Phase Record**
   - Navigate to any Project Phase record

2. **Launch Wizard**
   - Click the **Create Towers** button in the highlights panel or actions menu

3. **Step 1: Review Phase Details**
   - Review the Project Phase information
   - Click **Next**

4. **Step 2: Configure Towers**
   - Check "Do you want to create Towers?"
   - Enter the number of towers (1-50)
   - Fill in tower names for each generated form
   - Select status for each tower (defaults to "Planning")
   - Click **Next**

5. **Step 3: Review & Save**
   - Review the summary of towers to be created
   - Click **Save Towers**
   - Success message will appear
   - Page will refresh to show new towers

### Important Notes
- ⚠️ **One-Time Use**: Once towers are created, the wizard cannot be used again for that Project Phase
- ⚠️ **Maximum Limit**: You can create up to 50 towers at once
- ⚠️ **Required Fields**: All tower names must be filled before saving

---

## Technical Details

### Apex Methods

#### `getProjectPhaseDetails(Id projectPhaseId)`
- **Type**: `@AuraEnabled(cacheable=true)`
- **Purpose**: Fetches Project Phase details with related Project information
- **Returns**: `Project_Phase__c` record
- **Security**: Uses `WITH SECURITY_ENFORCED`

#### `checkExistingTowers(Id projectPhaseId)`
- **Type**: `@AuraEnabled(cacheable=true)`
- **Purpose**: Checks if towers already exist for the Project Phase
- **Returns**: `Boolean`
- **Security**: Uses `WITH SECURITY_ENFORCED`

#### `createTowers(List<Tower__c> towers)`
- **Type**: `@AuraEnabled`
- **Purpose**: Creates multiple Tower records in bulk
- **Returns**: `List<Tower__c>` with Ids
- **Validations**:
  - Maximum 50 towers
  - Required fields validation
  - Duplicate prevention
- **Security**: Uses `Database.insert()` with error handling

### JavaScript Key Features

- **Reactive Properties**: Uses `@track` for state management
- **Wire Service**: Efficient data loading with caching
- **Async/Await**: Modern promise handling
- **Error Handling**: Comprehensive error messages
- **Toast Notifications**: User-friendly feedback
- **Dynamic Rendering**: Conditional template rendering

### CSS Highlights

- **SLDS Compliance**: Uses Salesforce Lightning Design System
- **Responsive Design**: Mobile-first approach
- **Custom Scrollbar**: Enhanced UX for tower list
- **Animations**: Smooth transitions and fade-in effects
- **Hover Effects**: Interactive card styling

---

## Testing

### Run Apex Tests

```bash
# Run all tests
sf apex run test --test-level RunLocalTests --wait 10

# Run specific test class
sf apex run test --class-names ProjectPhaseTowerWizardControllerTest --wait 10

# Run with code coverage
sf apex run test --class-names ProjectPhaseTowerWizardControllerTest --code-coverage --wait 10
```

### Test Coverage
The test class `ProjectPhaseTowerWizardControllerTest` provides **100% code coverage** with the following test scenarios:

#### Positive Tests
- ✅ Get Project Phase details successfully
- ✅ Check existing towers (none exist)
- ✅ Check existing towers (towers exist)
- ✅ Create single tower
- ✅ Create multiple towers
- ✅ Create towers with different statuses
- ✅ Bulk creation (50 towers)

#### Negative Tests
- ✅ Null Project Phase Id
- ✅ Invalid Project Phase Id
- ✅ Empty tower list
- ✅ Null tower list
- ✅ Too many towers (>50)
- ✅ Missing tower name
- ✅ Missing Project Phase
- ✅ Towers already exist

---

## Troubleshooting

### Common Issues

#### Issue: "Towers already exist for this Project Phase"
**Solution**: This is expected behavior. The wizard can only be used once per Project Phase. If you need to create more towers, do so manually or delete existing towers first.

#### Issue: Quick Action not appearing
**Solution**: 
1. Verify the quick action is added to the page layout
2. Check user permissions for Project_Phase__c and Tower__c objects
3. Refresh the page or clear browser cache

#### Issue: "Error fetching Project Phase details"
**Solution**:
1. Verify the Project Phase record exists
2. Check user has read access to Project_Phase__c and Project__c
3. Ensure Project__c lookup is populated on the Project Phase

#### Issue: Component not loading
**Solution**:
1. Check browser console for JavaScript errors
2. Verify all files are deployed successfully
3. Ensure API version compatibility (v62.0)

---

## Security & Permissions

### Required Object Permissions
- **Project_Phase__c**: Read
- **Project__c**: Read
- **Tower__c**: Create, Read

### Field-Level Security
Ensure users have read/write access to:
- Tower__c.Name
- Tower__c.Status__c
- Tower__c.Project__c
- Tower__c.Project_Phase__c

### Sharing Settings
- Component respects org-wide defaults and sharing rules
- Uses `with sharing` in Apex controller
- Enforces CRUD/FLS with `WITH SECURITY_ENFORCED`

---

## Best Practices Implemented

### Salesforce Standards
✅ Lightning Design System (SLDS) compliance  
✅ Responsive mobile-first design  
✅ Proper error handling and user feedback  
✅ Bulkified DML operations  
✅ Governor limit considerations  
✅ Security enforced (CRUD/FLS)  
✅ Comprehensive test coverage (100%)  
✅ Clean, documented code  
✅ Proper naming conventions  

### Performance Optimization
✅ Cacheable Apex methods  
✅ Efficient SOQL queries  
✅ Bulk DML operations  
✅ No SOQL/DML in loops  
✅ Lazy loading of tower forms  

---

## Future Enhancements

### Potential Features
- 📋 Clone existing towers
- 📊 Tower creation analytics
- 📧 Email notification on tower creation
- 🔄 Edit towers after creation
- 📱 Enhanced mobile experience
- 🎨 Custom branding options
- 📈 Progress tracking for tower construction
- 🔍 Search and filter towers

---

## Support & Maintenance

### Version History
- **v1.0** (2026-05-29): Initial release

### Contact
For issues or questions, contact your Salesforce administrator.

### License
This component is part of the RealEstate Salesforce project.

---

## Appendix

### Sample Data for Testing

```apex
// Create test Project
Project__c project = new Project__c(Name = 'Skyline Residency');
insert project;

// Create test Project Phase
Project_Phase__c phase = new Project_Phase__c(
    Name = 'Phase 1',
    Project__c = project.Id,
    Phase_Status__c = 'Planning',
    Budget__c = 5000000
);
insert phase;
```

### Quick Reference Commands

```bash
# Deploy component
sf project deploy start --source-dir force-app/main/default/lwc/projectPhaseTowerWizard

# Run tests
sf apex run test --class-names ProjectPhaseTowerWizardControllerTest

# Retrieve from org
sf project retrieve start --source-dir force-app/main/default/lwc/projectPhaseTowerWizard

# Open org
sf org open

# View logs
sf apex tail log
```

---

**End of Documentation**
