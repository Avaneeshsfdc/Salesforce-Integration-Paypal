@IsTest
public class PayPalTestDataFactory {
    
    public static Account createTestAccount() {
        Account acc = new Account(
            Name = 'Test Account',
            BillingCity = 'San Francisco',
            BillingCountry = 'USA',
            BillingPostalCode = '94105'
        );
        insert acc;
        return acc;
    }
    
    public static Payment_Transaction__c createTestTransaction() {
        Account acc = createTestAccount();
        return createTestTransaction(acc.Id);
    }
    
    public static Payment_Transaction__c createTestTransaction(Id accountId) {
        Payment_Transaction__c transaction = new Payment_Transaction__c(
            PayPal_Order_ID__c = 'TEST_ORDER_' + System.currentTimeMillis(),
            Amount__c = 100.00,
            Currency_Code__c = 'USD',
            Status__c = 'Created',
            Account__c = accountId,
            Payment_Method__c = 'Credit Card',
            PayPal_Response__c = createMockPayPalResponse()
        );
        insert transaction;
        return transaction;
    }
    
    public static Payment_Transaction__c createCompletedTransaction() {
        Payment_Transaction__c transaction = createTestTransaction();
        transaction.Status__c = 'Completed';
        transaction.PayPal_Response__c = createMockCaptureResponse();
        update transaction;
        return transaction;
    }
    
    public static PayPal_Error_Log__c createErrorLog() {
        PayPal_Error_Log__c errorLog = new PayPal_Error_Log__c(
            Error_Type__c = 'API_ERROR',
            Error_Message__c = 'Test error message for unit testing',
            Transaction__c = createTestTransaction().Id
        );
        insert errorLog;
        return errorLog;
    }
    
    public static PayPal_Webhook_Log__c createWebhookLog() {
        PayPal_Webhook_Log__c webhookLog = new PayPal_Webhook_Log__c(
            Event_Type__c = 'PAYMENT.CAPTURE.COMPLETED',
            Event_ID__c = 'WH-TEST-' + System.currentTimeMillis(),
            Status__c = 'Received',
            Webhook_Data__c = createMockWebhookData(),
            Processed_Date__c = System.now()
        );
        insert webhookLog;
        return webhookLog;
    }
    
    public static String createMockPayPalResponse() {
        return JSON.serialize(new Map<String, Object>{
            'id' => 'TEST_ORDER_123',
            'status' => 'CREATED',
            'links' => new List<Map<String, String>>{
                new Map<String, String>{
                    'href' => 'https://api.sandbox.paypal.com/v2/checkout/orders/TEST_ORDER_123',
                    'rel' => 'self',
                    'method' => 'GET'
                },
                new Map<String, String>{
                    'href' => 'https://www.sandbox.paypal.com/checkoutnow?token=TEST_ORDER_123',
                    'rel' => 'approve',
                    'method' => 'GET'
                }
            },
            'purchase_units' => new List<Map<String, Object>>{
                new Map<String, Object>{
                    'reference_id' => 'PUHF',
                    'amount' => new Map<String, String>{
                        'currency_code' => 'USD',
                        'value' => '100.00'
                    }
                }
            }
        });
    }
    
    public static String createMockCaptureResponse() {
        return JSON.serialize(new Map<String, Object>{
            'id' => 'TEST_ORDER_123',
            'status' => 'COMPLETED',
            'purchase_units' => new List<Map<String, Object>>{
                new Map<String, Object>{
                    'payments' => new Map<String, Object>{
                        'captures' => new List<Map<String, Object>>{
                            new Map<String, Object>{
                                'id' => 'TEST_CAPTURE_123',
                                'status' => 'COMPLETED',
                                'amount' => new Map<String, String>{
                                    'currency_code' => 'USD',
                                    'value' => '100.00'
                                }
                            }
                        }
                    }
                }
            }
        });
    }
    
    public static String createMockWebhookData() {
        return JSON.serialize(new Map<String, Object>{
            'id' => 'WH-TEST-123',
            'event_type' => 'PAYMENT.CAPTURE.COMPLETED',
            'resource_type' => 'capture',
            'resource' => new Map<String, Object>{
                'id' => 'TEST_CAPTURE_123',
                'status' => 'COMPLETED',
                'amount' => new Map<String, String>{
                    'currency_code' => 'USD',
                    'value' => '100.00'
                }
            },
            'create_time' => '2024-01-01T00:00:00Z'
        });
    }
    
    public static String createMockErrorResponse() {
        return JSON.serialize(new Map<String, Object>{
            'name' => 'VALIDATION_ERROR',
            'message' => 'The requested action could not be performed',
            'debug_id' => 'test-debug-id-123',
            'details' => new List<Map<String, String>>{
                new Map<String, String>{
                    'issue' => 'INVALID_PARAMETER_VALUE',
                    'description' => 'Invalid parameter value'
                }
            }
        });
    }
    
    public static HttpResponse createSuccessfulHttpResponse(String body) {
        HttpResponse response = new HttpResponse();
        response.setStatusCode(201);
        response.setStatus('Created');
        response.setBody(body);
        response.setHeader('Content-Type', 'application/json');
        return response;
    }
    
    public static HttpResponse createErrorHttpResponse(Integer statusCode, String errorBody) {
        HttpResponse response = new HttpResponse();
        response.setStatusCode(statusCode);
        response.setStatus('Error');
        response.setBody(errorBody);
        response.setHeader('Content-Type', 'application/json');
        return response;
    }
}