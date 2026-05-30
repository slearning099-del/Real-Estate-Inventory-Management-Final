import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import calculateLoanAndSchedule from '@salesforce/apex/LoanCalculatorService.calculateLoanAndSchedule';
import { getFieldValue, getRecord } from 'lightning/uiRecordApi';

import CUSTOMER_UNIT_PAYMENT_OBJECT from '@salesforce/schema/Customer_unit_Payment__c';
import PROPERTY_PAYMENT_FIELD from '@salesforce/schema/Customer_unit_Payment__c.Property_Payment__c';
import TOKEN_AMOUNT_FIELD from '@salesforce/schema/Customer_unit_Payment__c.Token_Amount__c';
import DOWN_PAYMENT_FIELD from '@salesforce/schema/Customer_unit_Payment__c.Down_Payment__c';

export default class LoanCalculator extends LightningElement {

    @api recordId;
    @api objectApiName;

    @track propertyPrice = '';
    @track tokenAmount = '';
    @track downPayment = '';
    @track interestRate = 7.10;
    @track loanTenure = 5;
    @track emiNumber = '';

    @track calculatedLoanAmount = 0;
    @track monthlyEmi = 0;
    @track totalPayment = 0;
    @track totalInterest = 0;

    @track paymentSchedule = [];
    @track isCalculating = false;

    hasPrefilledAmounts = false;

    scheduleColumns = [
        { label: 'Installment #', fieldName: 'Installment_Number__c', type: 'number' },
        { label: 'Payment Type', fieldName: 'Payment_Type__c', type: 'text' },
        { label: 'Due Date', fieldName: 'Due_Date__c', type: 'date' },
        { label: 'Paid Amount', fieldName: 'Paid_Amount__c', type: 'currency' },
        { label: 'Status', fieldName: 'Status__c', type: 'text' }
    ];

    connectedCallback() {
        // Keep EMI number in sync with default tenure on first render
        this.emiNumber = this.loanTenure * 12;
    }

    get isCustomerUnitPaymentRecord() {
        return this.objectApiName === CUSTOMER_UNIT_PAYMENT_OBJECT.objectApiName;
    }

    @wire(getRecord, { recordId: '$recordId', fields: [PROPERTY_PAYMENT_FIELD, TOKEN_AMOUNT_FIELD, DOWN_PAYMENT_FIELD] })
    wiredCustomerUnitPayment({ data, error }) {
        if (error) {
            // Avoid spamming toast when embedded on non-record pages
            if (this.recordId) {
                this.showToast('Error', 'Unable to load payment details from record', 'error');
            }
            return;
        }
        if (!data) return;
        // `objectApiName` is not guaranteed to be provided in every hosting context.
        // If it is present, ensure we're on the expected object; otherwise, prefill opportunistically.
        if (this.objectApiName && !this.isCustomerUnitPaymentRecord) return;
        if (this.hasPrefilledAmounts) return;

        const propertyPayment = getFieldValue(data, PROPERTY_PAYMENT_FIELD);
        const tokenAmount = getFieldValue(data, TOKEN_AMOUNT_FIELD);
        const downPayment = getFieldValue(data, DOWN_PAYMENT_FIELD);

        // Prefill once; allow user to override afterwards
        // In some orgs, `Property_Payment__c` is stored as the *remaining amount* (already excluding token/down).
        // If we detect token+down >= propertyPayment, treat propertyPayment as balance and reconstruct full property price.
        const tokenNum = tokenAmount == null ? null : Number(tokenAmount);
        const downNum = downPayment == null ? null : Number(downPayment);
        const propertyNum = propertyPayment == null ? null : Number(propertyPayment);

        if (
            Number.isFinite(propertyNum) &&
            Number.isFinite(tokenNum) &&
            Number.isFinite(downNum) &&
            propertyNum > 0 &&
            (propertyNum - (tokenNum + downNum)) <= 0
        ) {
            this.propertyPrice = propertyNum + tokenNum + downNum;
        } else {
            this.propertyPrice = propertyPayment ?? '';
        }
        this.tokenAmount = tokenAmount ?? '';
        this.downPayment = downPayment ?? '';
        this.hasPrefilledAmounts = true;
        
        // Auto-calculate loan after loading record values
        if (this.propertyPrice && this.interestRate && this.loanTenure) {
            this.calculateLoan();
        }
    }

    // ✅ SHOW TABLE ONLY IF DATA EXISTS
    get hasSchedule() {
        return this.paymentSchedule && this.paymentSchedule.length > 0;
    }

    get paymentScheduleRows() {
        // `lightning-datatable` requires a stable unique key field.
        return (this.paymentSchedule || []).map((row, idx) => ({
            ...row,
            rowKey: row.Id || `${row.Installment_Number__c || 'row'}-${idx}`
        }));
    }

    // ✅ DISABLE DOWNLOAD BUTTON WHEN CALCULATING OR NO SCHEDULE
    get isDownloadButtonDisabled() {
        return this.isCalculating || !this.hasSchedule;
    }

    // =========================
    // INPUT HANDLERS
    // =========================
    handlePropertyPriceChange(e) {
        this.propertyPrice = e.target.value ? parseFloat(e.target.value) : '';
        // Auto-calculate if we have all required fields
        this.triggerAutoCalculation();
    }

    handleTokenAmountChange(e) {
        this.tokenAmount = e.target.value ? parseFloat(e.target.value) : '';
    }

    handleDownPaymentChange(e) {
        this.downPayment = e.target.value ? parseFloat(e.target.value) : '';
    }

    handleInterestRateChange(e) {
        this.interestRate = e.target.value ? parseFloat(e.target.value) : 7.10;
        console.log('Interest Rate Changed to:', this.interestRate);
        // Auto-calculate loan when interest rate changes
        this.triggerAutoCalculation();
    }

    handleLoanTenureChange(e) {
        this.loanTenure = e.target.value ? parseInt(e.target.value) : 5;
        this.emiNumber = this.loanTenure * 12;
        console.log('Loan Tenure Changed to:', this.loanTenure);
        // Auto-calculate loan when tenure changes
        this.triggerAutoCalculation();
    }

    triggerAutoCalculation() {
        // Only auto-calculate if we have property price, interest rate, and tenure
        if (Number.isFinite(this.propertyPrice) && this.propertyPrice > 0 &&
            Number.isFinite(this.interestRate) && this.interestRate >= 0 &&
            Number.isFinite(this.loanTenure) && this.loanTenure > 0) {
            this.calculateLoan();
        }
    }

    // =========================
    // MAIN FUNCTION
    // =========================
    async calculateLoan() {

        if (!this.propertyPrice || !this.interestRate || !this.loanTenure) {
            this.showToast('Error', 'Please fill required fields', 'error');
            return;
        }

        const propertyPriceNum = parseFloat(this.propertyPrice);
        const tokenAmountNum = parseFloat(this.tokenAmount) || 0;
        const downPaymentNum = parseFloat(this.downPayment) || 0;
        const interestRateNum = parseFloat(this.interestRate);
        const loanTenureYearsNum = parseInt(this.loanTenure);

        if (!Number.isFinite(propertyPriceNum) || propertyPriceNum <= 0) {
            this.showToast('Error', 'Property Price must be greater than 0', 'error');
            return;
        }
        if (!Number.isFinite(interestRateNum) || interestRateNum < 0) {
            this.showToast('Error', 'Interest Rate must be 0 or greater', 'error');
            return;
        }
        if (!Number.isFinite(tokenAmountNum) || tokenAmountNum < 0) {
            this.showToast('Error', 'Token Amount cannot be negative', 'error');
            return;
        }
        if (!Number.isFinite(downPaymentNum) || downPaymentNum < 0) {
            this.showToast('Error', 'Down Payment cannot be negative', 'error');
            return;
        }

        const loanAmountNum = propertyPriceNum - (tokenAmountNum + downPaymentNum);
        if (loanAmountNum <= 0) {
            this.showToast(
                'Error',
                'Loan Amount must be greater than 0. Please ensure Property Price is greater than (Token Amount + Down Payment).',
                'error'
            );
            return;
        }

        this.isCalculating = true;

        try {

            const response = await calculateLoanAndSchedule({
                propertyPrice: propertyPriceNum,
                tokenAmount: tokenAmountNum,
                downPayment: downPaymentNum,
                interestRate: interestRateNum,
                loanTenureYears: loanTenureYearsNum
            });

            console.log('Apex Response:', response);

            if (response.error) {
                this.showToast('Error', response.error, 'error');
                return;
            }

            // ✅ SUMMARY
            this.calculatedLoanAmount = response.loanAmount;
            this.monthlyEmi = response.monthlyEmi;
            this.totalPayment = response.totalPayment;
            this.totalInterest = response.totalInterest;

            // 🔥 CRITICAL FIX (force re-render)
            this.paymentSchedule = [...(response.scheduleList || [])];

            // 🔥 OPTIONAL: JS total calculation (backup)
            this.totalPayment = this.paymentSchedule.reduce(
                (sum, item) => sum + (item.Total_Amount__c || 0),
                0
            );

        } catch (error) {
            console.error('Error:', error);
            this.showToast('Error', 'Something went wrong', 'error');
        } finally {
            this.isCalculating = false;
        }
    }

    // =========================
    // TOAST
    // =========================
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }

    // =========================
    // RESET
    // =========================
    resetForm() {
        this.propertyPrice = '';
        this.tokenAmount = '';
        this.downPayment = '';
        this.interestRate = 7.10;
        this.loanTenure = 5;
        this.emiNumber = this.loanTenure * 12;
        this.hasPrefilledAmounts = false;

        this.calculatedLoanAmount = 0;
        this.monthlyEmi = 0;
        this.totalPayment = 0;
        this.totalInterest = 0;
        this.paymentSchedule = [];
    }

    // =========================
    // DOWNLOAD PDF
    // =========================
    downloadPdf() {
        // Create a simple text file with loan details
        const content = this.generatePdfContent();
        const blob = new Blob([content], { type: 'text/plain' });
        const url = window.URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = 'loan_details.txt';
        document.body.appendChild(a);
        a.click();
        window.URL.revokeObjectURL(url);
        document.body.removeChild(a);
    }

    // Generate content for PDF/text file
    generatePdfContent() {
        let content = '';
        content += 'LOAN CALCULATION DETAILS\n';
        content += '========================\n\n';
        
        content += `Property Price: ${this.propertyPrice}\n`;
        content += `Token Amount: ${this.tokenAmount}\n`;
        content += `Down Payment: ${this.downPayment}\n`;
        content += `Interest Rate: ${this.interestRate}%\n`;
        content += `Loan Tenure: ${this.loanTenure} years\n\n`;
        
        content += 'LOAN SUMMARY\n';
        content += '============\n';
        content += `Loan Amount: ${this.calculatedLoanAmount}\n`;
        content += `Monthly EMI: ${this.monthlyEmi}\n`;
        content += `Total Payment: ${this.totalPayment}\n`;
        content += `Total Interest: ${this.totalInterest}\n\n`;
        
        content += 'PAYMENT SCHEDULE\n';
        content += '================\n';
        content += 'Installment # | Payment Type | Due Date | Paid Amount | Status\n';
        content += '-----------------------------------------------------------\n';
        
        // Format payment schedule without Total Amount column
        this.paymentSchedule.forEach(schedule => {
            // Format the date properly for text file
            const dueDate = schedule.Due_Date__c ? new Date(schedule.Due_Date__c).toLocaleDateString() : '';
            content += `${schedule.Installment_Number__c} | ${schedule.Payment_Type__c} | ${dueDate} | ${schedule.Paid_Amount__c} | ${schedule.Status__c}\n`;
        });
        
        return content;
    }
}