# Project Wizard LWC Component

## Overview
The Project Wizard is a comprehensive Lightning Web Component designed to manage project phases and tower creation in Salesforce. It provides a step-by-step guided experience with form validation and data management capabilities.

## Features

### Step 1: Project Phase Details
- **Project Phase Selection**: Dropdown list to select from all available project phases
- **Phase Details Display**: Shows comprehensive information about the selected phase including:
  - Project Phase Name
  - Associated Project
  - Status

### Step 2: Tower Creation
- **Checkbox Option**: "Do you want to create tower(s)?"
- **Dynamic Tower Forms**: Once checkbox is enabled:
  - Input field to specify the number of towers (1-10)
  - Dynamic generation of form fields for each tower
  - Each tower card displays fields for:
    - **Tower Name** (required, text input)
    - **Status** (required, picklist with "Planning" option)
    - **Project** (required, lookup to Project object)
    - **Project Phase** (required, lookup to Project_Phase__c object)

## Component Features

✅ **Attractive Salesforce UI**
- Uses Lightning Card for clean layout
- Responsive design for mobile and desktop
- Custom CSS with Salesforce styling guidelines
- Success and error message toasts

✅ **One-Time Execution**
- Component tracks completion state
- Prevents multiple submissions
- Once submitted, wizard becomes locked
- Users cannot modify or resubmit after completion

✅ **Form Validation**
- Real-time validation of all required fields
- Submit button disabled until all fields are valid
- Specific error messages for different scenarios

✅ **Data Management**
- Batch creation of multiple Tower records
- Related data fetching from Project_Phase__c
- Error handling with detailed feedback
- Loading spinner during data operations

## File Structure

```
force-app/main/default/
├── lwc/
│   └── projectWizard/
│       ├── projectWizard.html      (Template)
│       ├── projectWizard.js         (Component Logic)
│       ├── projectWizard.css        (Styling)
│       └── projectWizard.js-meta.xml (Metadata)
└── classes/
    ├── ProjectWizardController.cls        (Apex Controller)
    └── ProjectWizardController.cls-meta.xml (Metadata)
```

## Usage

### 1. Adding to App Page
1. Navigate to App Builder
2. Add the "Project Wizard" component to the page
3. Configure properties if needed (title, etc.)

### 2. Adding to Record Page
1. Go to any Lightning Record Page
2. Click Edit
3. Add "Project Wizard" component
4. Save and activate the page

### 3. Using the Wizard

**Step 1 - Select Project Phase:**
- Select a project phase from the dropdown
- View the details of the selected phase

**Step 2 - Create Towers (Optional):**
- Check "Do you want to create tower(s)?" if you need to create towers
- Enter the number of towers you want to create (1-10)
- Fill in the required information for each tower:
  - Tower Name
  - Status (defaults to "Planning")
  - Project
  - Project Phase

**Step 3 - Submit:**
- Click "Submit" to create the towers
- System will validate all data before creation
- Success message displays number of towers created
- Component becomes locked after successful submission

**Cancel:**
- Click "Cancel" to reset the form
- Only available before submission

## Apex Controller Methods

### `getProjectPhases()`
- **Returns**: List of all Project Phase records with related project information
- **Cacheable**: Yes
- **SOQL Limit**: 1000 records

### `getProjects()`
- **Returns**: List of all Project records
- **Cacheable**: Yes
- **SOQL Limit**: 1000 records

### `getProjectPhaseDetails(projectPhaseId)`
- **Parameters**: Project Phase ID
- **Returns**: Map containing project phase details including related project name
- **Cacheable**: Yes

### `createTowers(towersJson)`
- **Parameters**: JSON string array of tower objects
- **Returns**: List of created Tower records
- **Cacheable**: No
- **Features**:
  - Batch insertion
  - Detailed error handling
  - Partial success tracking

## Component Configuration

### Targets
- lightning__AppPage
- lightning__RecordPage
- lightning__HomePage

### Configurable Properties
- `title`: Component title (default: "Project Wizard")

## Styling

The component uses:
- **Salesforce Lightning Design System (SLDS)** classes
- **Custom CSS** with responsive design
- **Salesforce Brand Colors**:
  - Primary Blue: #0070d2
  - Success Green: #04844b
  - Error Red: #c23030

### Responsive Breakpoints
- Mobile: < 768px
- Desktop: ≥ 768px

## Error Handling

The component handles various error scenarios:
1. Data loading failures
2. Form validation errors
3. Record creation failures
4. Network errors

All errors are displayed with user-friendly messages using toast notifications.

## Object References

### Tower__c Object
```apex
Field          | Type        | Description
============================================
Name           | Text        | Tower name
Status__c      | Picklist    | Tower status
Project__c     | Lookup      | Related project
Project_Phase__c | Lookup    | Related project phase
```

### Related Objects
- **Project__c**: Project object referenced via Tower__c.Project__c
- **Project_Phase__c**: Project Phase object referenced via Tower__c.Project_Phase__c

## Limitations

1. **One-Time Use**: Component can only be used once per session
2. **Tower Limit**: Maximum 10 towers can be created at once
3. **API Version**: Requires API version 59.0 or higher

## Future Enhancements

Potential improvements:
- Export created records to PDF/CSV
- Bulk update existing towers
- Integration with other components
- Advanced search and filtering
- Scheduling and workflow integration

## Support

For issues or questions:
1. Check the browser console for error messages
2. Review Apex logs for backend errors
3. Verify that all required objects and fields exist in your org
4. Ensure proper permissions are set for Tower__c object

## Version History

- **v1.0** (May 2026): Initial release with core functionality
  - Project Phase selection
  - Dynamic tower creation forms
  - Batch tower creation
  - One-time execution protection
  - Responsive UI design
