public with sharing class PaymentProcessor {
    
    public enum PaymentIntent {
        CAPTURE,
        AUTHORIZE
    }
    
    public enum PaymentType {
        ONE_TIME,
        RECURRING,
        SUBSCRIPTION
    }
    
    public class PaymentRequest {
        public Decimal amount;
        public String currencyCode;
        public String description;
        public Id recordId;
        public PaymentIntent intent = PaymentIntent.CAPTURE;
        public PaymentType paymentType;
        public String returnUrl;
        public String cancelUrl;
        public Map<String, Object> customData;
        
        public PaymentRequest() {
            this.customData = new Map<String, Object>();
            // Initialize payment type - will be set by caller or use helper method
        }
    }
    
    public class PaymentResult {
        public Boolean success;
        public String orderId;
        public String status;
        public String approvalUrl;
        public String errorMessage;
        public Payment_Transaction__c paymentTransaction;
        
        public PaymentResult() {
            this.success = false;
        }
    }
    
    public static PaymentRequest createOneTimePaymentRequest() {
        PaymentRequest request = new PaymentRequest();
        request.paymentType = PaymentType.ONE_TIME;
        return request;
    }
    
    public static PaymentResult processPayment(PaymentRequest request) {
        PaymentResult result = new PaymentResult();
        
        try {
            validatePaymentRequest(request);
            
            switch on request.paymentType {
                when ONE_TIME {
                    result = processOneTimePayment(request);
                }
                when RECURRING {
                    result = processRecurringPayment(request);
                }
                when SUBSCRIPTION {
                    result = processSubscriptionPayment(request);
                }
                when else {
                    throw new PayPalException('Unsupported payment type: ' + request.paymentType, 'VALIDATION_ERROR');
                }
            }
            
        } catch (PayPalException e) {
            result.success = false;
            result.errorMessage = e.getMessage();
            e.logError();
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = 'Unexpected error: ' + e.getMessage();
            
            PayPalException paypalEx = new PayPalException('Payment processing error: ' + e.getMessage(), 'SYSTEM_ERROR');
            paypalEx.logError();
        }
        
        return result;
    }
    
    private static void validatePaymentRequest(PaymentRequest request) {
        if (request.amount == null || request.amount <= 0) {
            throw new PayPalException('Payment amount must be greater than zero', 'VALIDATION_ERROR');
        }
        
        if (String.isBlank(request.currencyCode)) {
            throw new PayPalException('Currency code is required', 'VALIDATION_ERROR');
        }
        
        if (String.isBlank(request.description)) {
            throw new PayPalException('Payment description is required', 'VALIDATION_ERROR');
        }
        
        if (request.amount > 10000) {
            throw new PayPalException('Payment amount exceeds maximum limit', 'VALIDATION_ERROR');
        }
        
        Set<String> supportedCurrencies = new Set<String>{'USD', 'EUR', 'GBP', 'CAD', 'AUD', 'JPY'};
        if (!supportedCurrencies.contains(request.currencyCode.toUpperCase())) {
            throw new PayPalException('Unsupported currency: ' + request.currencyCode, 'VALIDATION_ERROR');
        }
    }
    
    private static PaymentResult processOneTimePayment(PaymentRequest request) {
        PaymentResult result = new PaymentResult();
        
        try {
            PayPalService.PayPalOrderResponse orderResponse = PayPalService.createOrder(
                request.amount,
                request.currencyCode,
                request.description,
                request.recordId
            );
            
            result.success = true;
            result.orderId = orderResponse.id;
            result.status = orderResponse.status;
            
            for (PayPalService.Link link : orderResponse.links) {
                if (link.rel == 'approve') {
                    result.approvalUrl = link.href;
                    break;
                }
            }
            
            result.paymentTransaction = getTransactionByOrderId(orderResponse.id);
            
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage();
            throw new PayPalException('One-time payment processing failed: ' + e.getMessage(), 'API_ERROR');
        }
        
        return result;
    }
    
    private static PaymentResult processRecurringPayment(PaymentRequest request) {
        throw new PayPalException('Recurring payments not yet implemented', 'SYSTEM_ERROR');
    }
    
    private static PaymentResult processSubscriptionPayment(PaymentRequest request) {
        throw new PayPalException('Subscription payments not yet implemented', 'SYSTEM_ERROR');
    }
    
    public static PaymentResult capturePayment(String orderId) {
        PaymentResult result = new PaymentResult();
        
        try {
            PayPalService.PayPalOrderResponse captureResponse = PayPalService.captureOrder(orderId);
            
            result.success = true;
            result.orderId = captureResponse.id;
            result.status = captureResponse.status;
            result.paymentTransaction = getTransactionByOrderId(orderId);
            
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage();
            
            PayPalException paypalEx = new PayPalException('Payment capture failed: ' + e.getMessage(), 'API_ERROR', '', orderId);
            paypalEx.logError();
        }
        
        return result;
    }
    
    public static PaymentResult refundPayment(String orderId, Decimal refundAmount, String currencyCode) {
        PaymentResult result = new PaymentResult();
        
        try {
            String refundResult = PayPalService.refundPayment(orderId, refundAmount, currencyCode);
            
            result.success = true;
            result.orderId = orderId;
            result.status = 'Refunded';
            result.paymentTransaction = getTransactionByOrderId(orderId);
            
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage();
            
            PayPalException paypalEx = new PayPalException('Payment refund failed: ' + e.getMessage(), 'API_ERROR', '', orderId);
            paypalEx.logError();
        }
        
        return result;
    }
    
    private static Payment_Transaction__c getTransactionByOrderId(String orderId) {
        try {
            return [
                SELECT Id, Name, PayPal_Order_ID__c, Amount__c, Currency_Code__c, 
                       Status__c, Payment_Method__c, CreatedDate, LastModifiedDate
                FROM Payment_Transaction__c 
                WHERE PayPal_Order_ID__c = :orderId 
                LIMIT 1
            ];
        } catch (Exception e) {
            System.debug('Failed to retrieve transaction: ' + e.getMessage());
            return null;
        }
    }
    
    @AuraEnabled
    public static PaymentResult processQuickPayment(Decimal amount, String currencyCode, String description, Id recordId) {
        PaymentRequest request = new PaymentRequest();
        request.amount = amount;
        request.currencyCode = currencyCode;
        request.description = description;
        request.recordId = recordId;
        
        return processPayment(request);
    }
    
    @AuraEnabled
    public static PaymentResult captureQuickPayment(String orderId) {
        return capturePayment(orderId);
    }
    
    @AuraEnabled
    public static PaymentResult processRefund(String orderId, Decimal refundAmount, String currencyCode) {
        return refundPayment(orderId, refundAmount, currencyCode);
    }
    
    public static void processWebhookEvent(String eventType, String resourceId, Map<String, Object> eventData) {
        try {
            switch on eventType {
                when 'PAYMENT.CAPTURE.COMPLETED' {
                    handlePaymentCompleted(resourceId, eventData);
                }
                when 'PAYMENT.CAPTURE.DENIED' {
                    handlePaymentDenied(resourceId, eventData);
                }
                when 'PAYMENT.CAPTURE.REFUNDED' {
                    handlePaymentRefunded(resourceId, eventData);
                }
                when 'CHECKOUT.ORDER.APPROVED' {
                    handleOrderApproved(resourceId, eventData);
                }
                when else {
                    System.debug('Unhandled webhook event: ' + eventType);
                }
            }
        } catch (Exception e) {
            PayPalException paypalEx = new PayPalException('Webhook processing failed: ' + e.getMessage(), 'SYSTEM_ERROR');
            paypalEx.logError();
        }
    }
    
    private static void handlePaymentCompleted(String resourceId, Map<String, Object> eventData) {
        List<Payment_Transaction__c> transactions = [
            SELECT Id, Status__c 
            FROM Payment_Transaction__c 
            WHERE PayPal_Order_ID__c = :resourceId
        ];
        
        if (!transactions.isEmpty()) {
            transactions[0].Status__c = 'Completed';
            update transactions;
        }
    }
    
    private static void handlePaymentDenied(String resourceId, Map<String, Object> eventData) {
        List<Payment_Transaction__c> transactions = [
            SELECT Id, Status__c 
            FROM Payment_Transaction__c 
            WHERE PayPal_Order_ID__c = :resourceId
        ];
        
        if (!transactions.isEmpty()) {
            transactions[0].Status__c = 'Failed';
            update transactions;
        }
    }
    
    private static void handlePaymentRefunded(String resourceId, Map<String, Object> eventData) {
        List<Payment_Transaction__c> transactions = [
            SELECT Id, Status__c, Amount__c
            FROM Payment_Transaction__c 
            WHERE PayPal_Order_ID__c = :resourceId
        ];
        
        if (!transactions.isEmpty()) {
            Map<String, Object> amount = (Map<String, Object>) eventData.get('amount');
            Decimal refundAmount = Decimal.valueOf((String) amount.get('value'));
            
            if (refundAmount == transactions[0].Amount__c) {
                transactions[0].Status__c = 'Refunded';
            } else {
                transactions[0].Status__c = 'Partially Refunded';
            }
            update transactions;
        }
    }
    
    private static void handleOrderApproved(String resourceId, Map<String, Object> eventData) {
        List<Payment_Transaction__c> transactions = [
            SELECT Id, Status__c 
            FROM Payment_Transaction__c 
            WHERE PayPal_Order_ID__c = :resourceId
        ];
        
        if (!transactions.isEmpty()) {
            transactions[0].Status__c = 'Approved';
            update transactions;
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getPaymentStats(Id recordId) {
        try {
            List<AggregateResult> stats = [
                SELECT COUNT(Id) totalCount, 
                       SUM(Amount__c) totalAmount,
                       Status__c status
                FROM Payment_Transaction__c 
                WHERE Account__c = :recordId
                GROUP BY Status__c
            ];
            
            Map<String, Object> result = new Map<String, Object>{
                'totalTransactions' => 0,
                'totalAmount' => 0,
                'statusBreakdown' => new Map<String, Object>()
            };
            
            Integer totalCount = 0;
            Decimal totalAmount = 0;
            Map<String, Object> statusBreakdown = new Map<String, Object>();
            
            for (AggregateResult ar : stats) {
                Integer count = (Integer) ar.get('totalCount');
                Decimal amount = (Decimal) ar.get('totalAmount');
                String status = (String) ar.get('status');
                
                totalCount += count;
                totalAmount += (amount != null ? amount : 0);
                
                statusBreakdown.put(status, new Map<String, Object>{
                    'count' => count,
                    'amount' => amount
                });
            }
            
            result.put('totalTransactions', totalCount);
            result.put('totalAmount', totalAmount);
            result.put('statusBreakdown', statusBreakdown);
            
            return result;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving payment statistics: ' + e.getMessage());
        }
    }
}