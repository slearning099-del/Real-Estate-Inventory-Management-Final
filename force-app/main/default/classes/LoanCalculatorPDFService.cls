public with sharing class LoanCalculatorPDFService {
    
    @AuraEnabled
    public static String generateLoanCalculationPDF(
        String propertyTower,
        String propertyUnit,
        String subUnit,
        Decimal propertyPrice,
        Decimal tokenAmount,
        Decimal downPayment,
        Decimal loanAmount,
        Decimal interestRate,
        Integer loanTenureYears,
        Decimal monthlyEMI,
        Decimal totalPayment,
        Decimal totalInterest,
        String emiNumber,
        List<PaymentScheduleItem> paymentSchedule
    ) {
        try {
            // Generate text-based PDF content
            String pdfContent = generateTextPDFContent(
                propertyTower,
                propertyUnit,
                subUnit,
                propertyPrice,
                tokenAmount,
                downPayment,
                loanAmount,
                interestRate,
                loanTenureYears,
                monthlyEMI,
                totalPayment,
                totalInterest,
                emiNumber,
                paymentSchedule
            );
            
            // Return the PDF content as a string that can be downloaded as a text file
            // Ensure we return a non-null value
            return pdfContent != null ? pdfContent : 'ERROR: Failed to generate PDF content';
        } catch (Exception e) {
            // Log the error and return error message
            System.debug('Error in generateLoanCalculationPDF: ' + e.getMessage());
            System.debug('Error stack trace: ' + e.getStackTraceString());
            return 'ERROR: ' + e.getMessage();
        }
    }
    
    private static String generateTextPDFContent(
        String propertyTower,
        String propertyUnit,
        String subUnit,
        Decimal propertyPrice,
        Decimal tokenAmount,
        Decimal downPayment,
        Decimal loanAmount,
        Decimal interestRate,
        Integer loanTenureYears,
        Decimal monthlyEMI,
        Decimal totalPayment,
        Decimal totalInterest,
        String emiNumber,
        List<PaymentScheduleItem> paymentSchedule
    ) {
        String safeTower = esc(propertyTower);
        String safeUnit = esc(propertyUnit);
        String safeSubUnit = esc(subUnit);
        String safeEmiNumber = esc(emiNumber);

        // Normalize numeric values with defaults
        Decimal dp = downPayment == null ? 0 : downPayment;
        Decimal la = loanAmount == null ? 0 : loanAmount;
        Decimal ir = interestRate == null ? 0 : interestRate;
        Integer tenure = loanTenureYears == null ? 0 : loanTenureYears;
        Decimal emi = monthlyEMI == null ? 0 : monthlyEMI;
        Decimal totPay = totalPayment == null ? 0 : totalPayment;
        Decimal totInt = totalInterest == null ? 0 : totalInterest;
        Decimal price = propertyPrice == null ? 0 : propertyPrice;
        Decimal token = tokenAmount == null ? 0 : tokenAmount;

        // Normalize schedule list
        List<PaymentScheduleItem> schedule = paymentSchedule == null ? new List<PaymentScheduleItem>() : paymentSchedule;

        // Build HTML content for a professional-looking PDF
        String html = '';
        html += '<h1 style="text-align:center;">Loan Calculation Report</h1>';
        html += '<p>Generated on: ' + Datetime.now().format() + '</p>';

        // Property info (optional display if provided)
        if (!String.isBlank(safeTower) || !String.isBlank(safeUnit) || !String.isBlank(safeSubUnit)) {
            html += '<h2>Property</h2>';
            html += '<table><tbody>';
            html += '<tr><th>Tower</th><td>' + safeTower + '</td></tr>';
            html += '<tr><th>Unit</th><td>' + safeUnit + '</td></tr>';
            html += '<tr><th>Sub Unit</th><td>' + safeSubUnit + '</td></tr>';
            html += '<tr><th>Property Price</th><td>$' + String.valueOf(price) + '</td></tr>';
            html += '<tr><th>Token Amount</th><td>$' + String.valueOf(token) + '</td></tr>';
            html += '</tbody></table>';
        }

        html += '<h2>Loan Details</h2>';
        html += '<table><tbody>';
        html += '<tr><th>Down Payment</th><td>$' + String.valueOf(dp) + '</td></tr>';
        html += '<tr><th>Loan Amount</th><td>$' + String.valueOf(la) + '</td></tr>';
        html += '<tr><th>Interest Rate</th><td>' + String.valueOf(ir) + '%</td></tr>';
        html += '<tr><th>Loan Tenure</th><td>' + String.valueOf(tenure) + ' Years</td></tr>';
        html += '<tr><th>Monthly EMI</th><td>$' + String.valueOf(emi) + '</td></tr>';
        html += '<tr><th>Total Payment</th><td>$' + String.valueOf(totPay) + '</td></tr>';
        html += '<tr><th>Total Interest</th><td>$' + String.valueOf(totInt) + '</td></tr>';
        html += '<tr><th>EMI Number</th><td>' + safeEmiNumber + '</td></tr>';
        html += '</tbody></table>';

        html += '<h2>Payment Schedule</h2>';
        html += '<table><thead>';
        html += '<tr><th>Payment Type</th><th>Payment Date</th><th>Installment #</th><th>Status</th><th>Due Date</th><th>Total Amount</th><th>Paid Amount</th></tr>';
        html += '</thead><tbody>';
        if (!schedule.isEmpty()) {
            for (PaymentScheduleItem item : schedule) {
                // Defensive null-safe conversions
                String payType = esc(item == null ? null : item.paymentType);
                String payDate = esc(item == null ? null : item.paymentDate);
                String status = esc(item == null ? null : item.status);
                String due = esc(item == null ? null : item.dueDate);
                Integer instNum = (item == null || item.installmentNumber == null) ? 0 : item.installmentNumber;
                Decimal tAmt = (item == null || item.totalAmount == null) ? 0 : item.totalAmount;
                Decimal pAmt = (item == null || item.paidAmount == null) ? 0 : item.paidAmount;

                html += '<tr>';
                html += '<td>' + payType + '</td>';
                html += '<td>' + payDate + '</td>';
                html += '<td>' + String.valueOf(instNum) + '</td>';
                html += '<td>' + status + '</td>';
                html += '<td>' + due + '</td>';
                html += '<td>$' + String.valueOf(tAmt) + '</td>';
                html += '<td>$' + String.valueOf(pAmt) + '</td>';
                html += '</tr>';
            }
        } else {
            html += '<tr><td colspan="7">No payment schedule data available</td></tr>';
        }
        html += '</tbody></table>';
        html += '<p style="margin-top:12px;font-size:11px;color:#666;">This is a system-generated document. Generated by Salesforce Loan Calculator Application.</p>';
        return html;
    }
    
    // Simple HTML escape helper to prevent injection
    private static String esc(String input) {
        if (input == null || input.trim().length() == 0) {
            return '';
        }
        String s = input;
        // Replace ampersand first to avoid double-encoding
        s = s.replace('&', '&');
        s = s.replace('<', '<');
        s = s.replace('>', '>');
        s = s.replace('"', '"');
        s = s.replace('\'', '&#39;');
        return s;
    }
    
    // Inner class to represent payment schedule items - using the same field names as LWC
    public class PaymentScheduleItem {
        @AuraEnabled public String paymentType;
        @AuraEnabled public String paymentDate;
        @AuraEnabled public Integer installmentNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String dueDate;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Decimal paidAmount;
        
        public PaymentScheduleItem(String paymentType, String paymentDate, Integer installmentNumber, 
                                  String status, String dueDate, Decimal totalAmount, Decimal paidAmount) {
            this.paymentType = paymentType;
            this.paymentDate = paymentDate;
            this.installmentNumber = installmentNumber;
            this.status = status;
            this.dueDate = dueDate;
            this.totalAmount = totalAmount;
            this.paidAmount = paidAmount;
        }
    }
}