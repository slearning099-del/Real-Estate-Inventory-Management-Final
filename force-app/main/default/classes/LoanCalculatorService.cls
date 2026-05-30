public with sharing class LoanCalculatorService {
    
    // =========================
    // RESPONSE CLASS
    // =========================
    public class LoanCalculationResponse {
        @AuraEnabled public Decimal loanAmount;
        @AuraEnabled public Decimal monthlyEmi;
        @AuraEnabled public Decimal totalPayment;
        @AuraEnabled public Decimal totalInterest;
        @AuraEnabled public Integer totalMonths;
        @AuraEnabled public String error;
        
        @AuraEnabled public List<Payment_Shcedule__c> scheduleList;
    }
    
    // =========================
    // LWC METHOD
    // =========================
    @AuraEnabled
    public static LoanCalculationResponse calculateLoanAndSchedule(
        Decimal propertyPrice,
        Decimal tokenAmount,
        Decimal downPayment,
        Decimal interestRate,
        Integer loanTenureYears
    ) {
        LoanCalculationResponse res = new LoanCalculationResponse();
        res.scheduleList = new List<Payment_Shcedule__c>();
        
        // 🔹 Null handling
        Decimal token = tokenAmount != null ? tokenAmount : 0;
        Decimal down = downPayment != null ? downPayment : 0;
        
        // 🔹 Validations
        if (propertyPrice == null || propertyPrice <= 0) {
            res.error = 'Invalid property price';
            return res;
        }
        
        if (interestRate == null || interestRate < 0) {
            res.error = 'Invalid interest rate';
            return res;
        }
        
        if (loanTenureYears == null || loanTenureYears <= 0) {
            res.error = 'Invalid loan tenure';
            return res;
        }
        
        // 🔹 Loan Amount
        Decimal loanAmount = propertyPrice - (token + down);
        
        if (loanAmount <= 0) {
            res.error = 'Loan amount cannot be zero or negative';
            return res;
        }
        
        Decimal monthlyRate = interestRate / (12 * 100);
        Integer totalMonths = loanTenureYears * 12;
        
        Decimal emi;
        
        // 🔹 EMI Calculation (FIXED pow issue)
        if (monthlyRate > 0) {
            Double base = (1 + monthlyRate).doubleValue();
            Double powValue = Math.pow(base, totalMonths);
            Decimal powResult = Decimal.valueOf(powValue);
            
            emi = (loanAmount * monthlyRate * powResult) / (powResult - 1);
        } else {
            emi = loanAmount / totalMonths;
        }
        
        // 🔥 IMPORTANT CHANGE: Calculate total from schedule
        Decimal totalScheduleAmount = 0;
        
        Date startDate = Date.today().addMonths(1);
        
        // =========================
        // 🔥 PAYMENT SCHEDULE
        // =========================
        for (Integer i = 1; i <= totalMonths; i++) {
            
            Payment_Shcedule__c ps = new Payment_Shcedule__c();
            
            ps.Payment_Type__c = 'Installment';
            ps.Installment_Number__c = i;
            ps.Due_Date__c = startDate.addMonths(i - 1);
            ps.Total_Amount__c = emi.setScale(2);
            
            // 🔥 YOUR REQUIREMENT CHANGE
            ps.Paid_Amount__c = emi.setScale(2);
            
            ps.Status__c = 'Pending';
            
            // 🔥 Sum of all installments
            totalScheduleAmount += emi;
            
            res.scheduleList.add(ps);
        }
        
        // 🔥 FINAL CALCULATIONS FROM SCHEDULE
        Decimal totalPayment = totalScheduleAmount;
        Decimal totalInterest = totalPayment - loanAmount;
        
        // 🔹 Set Summary
        res.loanAmount = loanAmount.setScale(2);
        res.monthlyEmi = emi.setScale(2);
        res.totalPayment = totalPayment.setScale(2);
        res.totalInterest = totalInterest.setScale(2);
        res.totalMonths = totalMonths;
        
        return res;
    }
}