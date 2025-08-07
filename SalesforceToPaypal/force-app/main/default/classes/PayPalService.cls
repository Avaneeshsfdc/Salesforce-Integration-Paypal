public with sharing class PayPalService {
    private static final String ORDERS_ENDPOINT = '/v2/checkout/orders';
    private static final String PAYMENTS_ENDPOINT = '/v2/payments';
    private static final String REFUNDS_ENDPOINT = '/v2/payments/refunds';
    
    public class PayPalOrderRequest {
        public String intent;
        public List<PurchaseUnit> purchase_units;
        public PaymentSource payment_source;
        public ApplicationContext application_context;
    }
    
    public class PurchaseUnit {
        public String reference_id;
        public Amount amount;
        public String description;
    }
    
    public class Amount {
        public String currency_code;
        public String value;
    }
    
    public class PaymentSource {
        public PaypalWallet paypal;
        public Card card;
    }
    
    public class PaypalWallet {
        public ExperienceContext experience_context;
    }
    
    public class Card {
        public String card_number;
        public String expiry;
        public String security_code;
    }
    
    public class ExperienceContext {
        public String return_url;
        public String cancel_url;
        public String brand_name;
        public String user_action;
        public String payment_method_preference;
    }
    
    public class ApplicationContext {
        public String brand_name;
        public String locale;
        public String landing_page;
        public String shipping_preference;
        public String user_action;
        public String return_url;
        public String cancel_url;
    }
    
    public class PayPalOrderResponse {
        public String id;
        public String status;
        public List<Link> links;
        public List<PurchaseUnit> purchase_units;
        public String create_time;
        public String update_time;
    }
    
    public class Link {
        public String href;
        public String rel;
        public String method;
    }
    
    @AuraEnabled
    public static PayPalOrderResponse createOrder(Decimal amount, String currencyCode, String description, Id accountId) {
        try {
            PayPalOrderRequest orderRequest = new PayPalOrderRequest();
            orderRequest.intent = 'CAPTURE';
            
            PurchaseUnit purchaseUnit = new PurchaseUnit();
            purchaseUnit.reference_id = 'PUHF';
            purchaseUnit.description = description;
            
            Amount amountObj = new Amount();
            amountObj.currency_code = currencyCode;
            amountObj.value = String.valueOf(amount);
            purchaseUnit.amount = amountObj;
            
            orderRequest.purchase_units = new List<PurchaseUnit>{ purchaseUnit };
            
            ApplicationContext appContext = new ApplicationContext();
            appContext.return_url = Url.getOrgDomainUrl().toExternalForm() + '/lightning/n/Payment_Success';
            appContext.cancel_url = Url.getOrgDomainUrl().toExternalForm() + '/lightning/n/Payment_Cancel';
            appContext.brand_name = 'Salesforce Integration';
            appContext.landing_page = 'LOGIN';
            appContext.user_action = 'PAY_NOW';
            orderRequest.application_context = appContext;
            
            String jsonRequest = JSON.serialize(orderRequest);
            
            HttpResponse response = PayPalHttpCallout.makeCallout('POST', ORDERS_ENDPOINT, jsonRequest);
            
            if (response.getStatusCode() == 201) {
                PayPalOrderResponse orderResponse = (PayPalOrderResponse) JSON.deserialize(response.getBody(), PayPalOrderResponse.class);
                
                Payment_Transaction__c paymentTransaction = new Payment_Transaction__c(
                    PayPal_Order_ID__c = orderResponse.id,
                    Amount__c = amount,
                    Currency_Code__c = currencyCode,
                    Status__c = 'Created',
                    Account__c = accountId,
                    PayPal_Response__c = response.getBody()
                );
                insert paymentTransaction;
                
                return orderResponse;
            } else {
                throw new PayPalException('Failed to create PayPal order', 'API_ERROR', response.getBody());
            }
            
        } catch (Exception e) {
            PayPalException paypalEx = new PayPalException('Error creating PayPal order: ' + e.getMessage(), 'SYSTEM_ERROR');
            paypalEx.logError();
            throw paypalEx;
        }
    }
    
    @AuraEnabled
    public static PayPalOrderResponse captureOrder(String orderId) {
        try {
            String endpoint = ORDERS_ENDPOINT + '/' + orderId + '/capture';
            HttpResponse response = PayPalHttpCallout.makeCallout('POST', endpoint, '{}');
            
            if (response.getStatusCode() == 201) {
                PayPalOrderResponse captureResponse = (PayPalOrderResponse) JSON.deserialize(response.getBody(), PayPalOrderResponse.class);
                
                Payment_Transaction__c paymentTransaction = [
                    SELECT Id, Status__c 
                    FROM Payment_Transaction__c 
                    WHERE PayPal_Order_ID__c = :orderId 
                    LIMIT 1
                ];
                
                paymentTransaction.Status__c = 'Completed';
                paymentTransaction.PayPal_Response__c = response.getBody();
                update paymentTransaction;
                
                return captureResponse;
            } else {
                throw new PayPalException('Failed to capture PayPal order', 'API_ERROR', response.getBody(), orderId);
            }
            
        } catch (Exception e) {
            PayPalException paypalEx = new PayPalException('Error capturing PayPal order: ' + e.getMessage(), 'SYSTEM_ERROR', '', orderId);
            paypalEx.logError();
            throw paypalEx;
        }
    }
    
    @AuraEnabled
    public static String refundPayment(String orderId, Decimal refundAmount, String currencyCode) {
        try {
            Payment_Transaction__c paymentTransaction = [
                SELECT Id, PayPal_Order_ID__c, Amount__c, Status__c, PayPal_Response__c
                FROM Payment_Transaction__c 
                WHERE PayPal_Order_ID__c = :orderId 
                LIMIT 1
            ];
            
            Map<String, Object> orderDetails = (Map<String, Object>) JSON.deserializeUntyped(paymentTransaction.PayPal_Response__c);
            List<Object> purchaseUnits = (List<Object>) orderDetails.get('purchase_units');
            Map<String, Object> firstUnit = (Map<String, Object>) purchaseUnits[0];
            Map<String, Object> payments = (Map<String, Object>) firstUnit.get('payments');
            List<Object> captures = (List<Object>) payments.get('captures');
            Map<String, Object> capture = (Map<String, Object>) captures[0];
            String captureId = (String) capture.get('id');
            
            Map<String, Object> refundRequest = new Map<String, Object>();
            refundRequest.put('amount', new Map<String, String>{
                'currency_code' => currencyCode,
                'value' => String.valueOf(refundAmount)
            });
            
            String endpoint = '/v2/payments/captures/' + captureId + '/refund';
            String jsonRequest = JSON.serialize(refundRequest);
            
            HttpResponse response = PayPalHttpCallout.makeCallout('POST', endpoint, jsonRequest);
            
            if (response.getStatusCode() == 201) {
                if (refundAmount == paymentTransaction.Amount__c) {
                    paymentTransaction.Status__c = 'Refunded';
                } else {
                    paymentTransaction.Status__c = 'Partially Refunded';
                }
                update paymentTransaction;
                
                return 'Refund successful';
            } else {
                throw new PayPalException('Failed to process refund', 'API_ERROR', response.getBody(), orderId);
            }
            
        } catch (Exception e) {
            PayPalException paypalEx = new PayPalException('Error processing refund: ' + e.getMessage(), 'SYSTEM_ERROR', '', orderId);
            paypalEx.logError();
            throw paypalEx;
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Payment_Transaction__c> getPaymentHistory(Id accountId) {
        try {
            return [
                SELECT Id, Name, PayPal_Order_ID__c, Amount__c, Currency_Code__c, 
                       Status__c, Payment_Method__c, CreatedDate
                FROM Payment_Transaction__c 
                WHERE Account__c = :accountId 
                ORDER BY CreatedDate DESC 
                LIMIT 50
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving payment history: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static Payment_Transaction__c getPaymentStatus(String orderId) {
        try {
            return [
                SELECT Id, Name, PayPal_Order_ID__c, Amount__c, Currency_Code__c, 
                       Status__c, Payment_Method__c, CreatedDate, LastModifiedDate
                FROM Payment_Transaction__c 
                WHERE PayPal_Order_ID__c = :orderId 
                LIMIT 1
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving payment status: ' + e.getMessage());
        }
    }
}