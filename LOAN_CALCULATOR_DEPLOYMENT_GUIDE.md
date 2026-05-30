# Loan Calculator Component - Deployment Guide

## Changes Made

### 1. Default Interest Rate
- ✅ Set default interest rate to **7.10%**
- ✅ Interest rate is editable by users via input field
- ✅ Dynamic EMI calculation updates automatically when interest rate changes

### 2. Automatic Calculation on Load
- ✅ Added `connectedCallback()` lifecycle hook
- ✅ EMI is now calculated automatically when component loads with default values
- ✅ Users see calculated values immediately without needing to input anything

### 3. Component Features
- Default Loan Amount: ₹10,00,000
- Default Tenure: 20 years
- Default Interest Rate: 7.10% (editable)
- All fields are editable and trigger automatic recalculation

## Making the Component Visible

### Option 1: Add to App Page
1. Go to **Setup** → **Lightning App Builder**
2. Create new or edit existing App Page
3. Drag **loanCalculator** component from left panel
4. Save and activate the page

### Option 2: Add to Record Page
1. Go to **Setup** → **Lightning App Builder**
2. Edit a Record Page (e.g., Account, Contact, Opportunity)
3. Drag **loanCalculator** component to desired location
4. Save and activate

### Option 3: Create Custom Tab
1. Go to **Setup** → **Tabs**
2. Click **New** in Lightning Component Tabs section
3. Select **c:loanCalculator** from Lightning Component dropdown
4. Configure tab label (e.g., "Loan Calculator")
5. Add tab to relevant apps

### Option 4: Add to Home Page
1. Go to **Setup** → **Lightning App Builder**
2. Edit Home Page
3. Drag **loanCalculator** component to desired region
4. Save and activate

## Redeployment Steps

If you need to redeploy the component:

```bash
# Deploy to org
sf project deploy start --source-dir force-app/main/default/lwc/loanCalculator

# Or deploy all metadata
sf project deploy start
```

## Testing the Component

1. Navigate to where you placed the component
2. Verify default values appear:
   - Loan Amount: 1000000
   - Tenure: 20
   - Interest Rate: 7.10
3. Verify EMI is calculated and displayed automatically
4. Change the interest rate and verify EMI updates
5. Change loan amount or tenure and verify EMI updates

## Component Metadata Configuration

The component is configured as:
- **API Version**: 62.0
- **Exposed**: true
- **Available for**: Lightning App Builder, Lightning Pages, Record Pages, Communities

## Troubleshooting

### Component Not Visible
- Check if component is added to a Lightning Page
- Verify page is activated
- Check if user has access to the page/app
- Clear browser cache and refresh

### Values Not Calculating
- Check browser console for JavaScript errors
- Verify component deployed successfully
- Check Apex class permissions if using backend calculations

### Interest Rate Not Editable
- Verified: Interest rate field has `onchange={handleInputChange}`
- Field is bound to `{interestRate}` which is @track decorated
- This should work correctly