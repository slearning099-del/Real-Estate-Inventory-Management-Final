/**
 * Service class to handle loan calculations and payment schedule generation
 */
public with sharing class LoanCalculationService {
    
    /**
     * Calculates the remaining loan amount based on property price, token amount and down payment
     * @param propertyPrice - The total price of the property
     * @param tokenAmount - The token amount paid by customer
     * @param downPayment - The down payment amount paid by customer
     * @return The remaining loan amount
     */
    public static Decimal calculateRemainingLoanAmount(Decimal propertyPrice, Decimal tokenAmount, Decimal downPayment) {
        return propertyPrice - (tokenAmount + downPayment);
    }
    
    /**
     * Calculates the monthly EMI based on loan amount, interest rate and tenure
     * @param loanAmount - The total loan amount
     * @param annualInterestRate - Annual interest rate (in percentage)
     * @param loanTenureYears - Loan tenure in years
     * @return Monthly EMI amount
     */
    public static Decimal calculateMonthlyEmi(Decimal loanAmount, Decimal annualInterestRate, Integer loanTenureYears) {
        if (loanAmount == null || annualInterestRate == null || loanTenureYears == null || loanTenureYears <= 0) {
            return 0;
        }
        
        Decimal monthlyInterestRate = annualInterestRate / (12 * 100);
        Integer totalMonths = loanTenureYears * 12;
        
        // Calculate EMI using formula: EMI = P * r * (1+r)^n / ((1+r)^n - 1)
        if (monthlyInterestRate > 0) {
            Double base = 1 + (Double)monthlyInterestRate;
            Double powerResult = Math.pow(base, (Double)totalMonths);
            Decimal numerator = loanAmount * monthlyInterestRate * powerResult;
            Decimal denominator = powerResult - 1;
            return numerator / denominator;
        } else {
            return loanAmount / totalMonths;
        }
    }
    
    /**
     * Generates payment schedule for a loan
     * @param loanAmount - The total loan amount
     * @param annualInterestRate - Annual interest rate (in percentage)
     * @param loanTenureYears - Loan tenure in years
     * @param tokenAmount - The token amount paid
     * @param downPayment - The down payment amount paid
     * @param paymentDate - The date of payment
     * @return List of Payment_Shcedule__c records
     */
    public static List<Payment_Shcedule__c> generatePaymentSchedule(
        Decimal loanAmount, 
        Decimal annualInterestRate, 
        Integer loanTenureYears,
        Decimal tokenAmount,
        Decimal downPayment,
        Date paymentDate,
        Id bookingId
    ) {
        List<Payment_Shcedule__c> scheduleList = new List<Payment_Shcedule__c>();
        
        // Calculate monthly interest rate and total months
        Decimal monthlyInterestRate = annualInterestRate / (12 * 100);
        Integer totalMonths = loanTenureYears * 12;
        
        // Calculate monthly EMI
        Decimal monthlyEmi = calculateMonthlyEmi(loanAmount, annualInterestRate, loanTenureYears);
        
        // Add Token Amount payment
        Payment_Shcedule__c tokenPayment = new Payment_Shcedule__c(
            Booking__c = bookingId,
            Payment_Type__c = 'Token Amount',
            Payment_Date__c = paymentDate,
            Due_Date__c = paymentDate,
            Total_Amount__c = tokenAmount,
            Paid_Amount__c = 0,
            Status__c = 'Paid'
        );
        scheduleList.add(tokenPayment);
        
        // Add Down Payment payment
        Payment_Shcedule__c downPaymentRecord = new Payment_Shcedule__c(
            Booking__c = bookingId,
            Payment_Type__c = 'Down Payment',
            Payment_Date__c = paymentDate,
            Due_Date__c = paymentDate,
            Total_Amount__c = downPayment,
            Paid_Amount__c = 0,
            Status__c = 'Paid'
        );
        scheduleList.add(downPaymentRecord);
        
        // Generate EMI schedule
        Decimal balance = loanAmount;
        for (Integer i = 1; i <= totalMonths; i++) {
            Decimal interestPayment = balance * monthlyInterestRate;
            Decimal principalPayment = monthlyEmi - interestPayment;
            balance -= principalPayment;
            
            if (balance < 0) balance = 0;
            
            // Calculate due date (next month)
            Date dueDate = paymentDate.addMonths(i);
            
            Payment_Shcedule__c emiPayment = new Payment_Shcedule__c(
                Booking__c = bookingId,
                Payment_Type__c = 'Installment',
                Payment_Date__c = paymentDate,
                Installment_Number__c = i,
                Due_Date__c = dueDate,
                Total_Amount__c = monthlyEmi,
                Paid_Amount__c = 0,
                Status__c = 'Pending'
            );
            scheduleList.add(emiPayment);
        }
        
        // Add Final Payment
        Payment_Shcedule__c finalPayment = new Payment_Shcedule__c(
            Booking__c = bookingId,
            Payment_Type__c = 'Final Payment',
            Payment_Date__c = paymentDate,
            Installment_Number__c = totalMonths + 1,
            Due_Date__c = paymentDate.addMonths(totalMonths + 1),
            Total_Amount__c = balance,
            Paid_Amount__c = 0,
            Status__c = 'Pending'
        );
        scheduleList.add(finalPayment);
        
        return scheduleList;
    }
}