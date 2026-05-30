/**
 * Test class for LoanCalculationService
 */
@isTest
public class LoanCalculationServiceTest {
    
    @isTest
    static void testCalculateRemainingLoanAmount() {
        // Test case 1: Normal calculation
        Decimal propertyPrice = 5000000;
        Decimal tokenAmount = 500000;
        Decimal downPayment = 1000000;
        
        Decimal result = LoanCalculationService.calculateRemainingLoanAmount(propertyPrice, tokenAmount, downPayment);
        System.assertEquals(3500000, result, 'Remaining loan amount should be 3,500,000');
        
        // Test case 2: Zero down payment
        Decimal result2 = LoanCalculationService.calculateRemainingLoanAmount(1000000, 100000, 0);
        System.assertEquals(900000, result2, 'Remaining loan amount should be 900,000');
        
        // Test case 3: Zero token amount
        Decimal result3 = LoanCalculationService.calculateRemainingLoanAmount(1000000, 0, 500000);
        System.assertEquals(500000, result3, 'Remaining loan amount should be 500,000');
    }
    
    @isTest
    static void testCalculateMonthlyEmi() {
        // Test case 1: Normal calculation with interest
        Decimal loanAmount = 3500000;
        Decimal interestRate = 8.5;
        Integer tenureYears = 10;
        
        Decimal result = LoanCalculationService.calculateMonthlyEmi(loanAmount, interestRate, tenureYears);
        System.assertNotEquals(0, result, 'EMI should not be zero');
        System.assert(result > 0, 'EMI should be positive');
        
        // Test case 2: Zero interest rate
        Decimal result2 = LoanCalculationService.calculateMonthlyEmi(1000000, 0, 5);
        System.assertEquals(20000, result2, 'EMI should be 20,000 with 0% interest');
        
        // Test case 3: Null values
        Decimal result3 = LoanCalculationService.calculateMonthlyEmi(null, 8.5, 10);
        System.assertEquals(0, result3, 'EMI should be 0 with null loan amount');
    }
    
    @isTest
    static void testGeneratePaymentSchedule() {
        // Create test data
        Decimal loanAmount = 3500000;
        Decimal interestRate = 8.5;
        Integer tenureYears = 10;
        Decimal tokenAmount = 500000;
        Decimal downPayment = 1000000;
        Date paymentDate = Date.today();
        Id bookingId = '000000000000000AAA'; // Dummy ID for testing
        
        // Generate payment schedule
        List<Payment_Shcedule__c> schedule = LoanCalculationService.generatePaymentSchedule(
            loanAmount, 
            interestRate, 
            tenureYears,
            tokenAmount,
            downPayment,
            paymentDate,
            bookingId
        );
        
        // Verify that we got a schedule
        System.assertNotEquals(null, schedule, 'Schedule should not be null');
        System.assert(schedule.size() > 0, 'Schedule should contain records');
        
        // Verify that we have the expected number of records
        // Should have: 1 token payment + 1 down payment + 120 EMIs + 1 final payment = 122 records
        System.assertEquals(122, schedule.size(), 'Should have 122 payment schedule records');
        
        // Verify first two records (token and down payment)
        Payment_Shcedule__c firstRecord = schedule[0];
        System.assertEquals('Token Amount', firstRecord.Payment_Type__c, 'First record should be Token Amount');
        System.assertEquals(tokenAmount, firstRecord.Total_Amount__c, 'Token amount should match');
        
        Payment_Shcedule__c secondRecord = schedule[1];
        System.assertEquals('Down Payment', secondRecord.Payment_Type__c, 'Second record should be Down Payment');
        System.assertEquals(downPayment, secondRecord.Total_Amount__c, 'Down payment amount should match');
        
        // Verify EMI records
        Payment_Shcedule__c emiRecord = schedule[2]; // Third record should be first EMI
        System.assertEquals('Installment', emiRecord.Payment_Type__c, 'Third record should be Installment');
        System.assert(emiRecord.Installment_Number__c > 0, 'Installment number should be greater than 0');
        System.assertEquals('Pending', emiRecord.Status__c, 'EMI should be pending');
    }
}