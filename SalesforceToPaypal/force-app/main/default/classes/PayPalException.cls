public class PayPalException extends Exception {
    public String errorCode { get; set; }
    public String errorDetails { get; set; }
    public String paypalOrderId { get; set; }
    
    public PayPalException(String message, String errorCode) {
        this(message);
        this.errorCode = errorCode;
    }
    
    public PayPalException(String message, String errorCode, String errorDetails) {
        this(message, errorCode);
        this.errorDetails = errorDetails;
    }
    
    public PayPalException(String message, String errorCode, String errorDetails, String paypalOrderId) {
        this(message, errorCode, errorDetails);
        this.paypalOrderId = paypalOrderId;
    }
    
    public void logError() {
        PayPal_Error_Log__c errorLog = new PayPal_Error_Log__c(
            Error_Message__c = this.getMessage(),
            Error_Type__c = this.errorCode
        );
        
        try {
            insert errorLog;
        } catch (Exception e) {
            System.debug('Failed to log PayPal error: ' + e.getMessage());
        }
    }
}