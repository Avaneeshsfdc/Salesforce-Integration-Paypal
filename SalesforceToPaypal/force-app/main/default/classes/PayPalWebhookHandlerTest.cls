@IsTest
public class PayPalWebhookHandlerTest {
    
    @TestSetup
    static void setupTestData() {
        PayPalTestDataFactory.createTestAccount();
    }
    
    @IsTest
    static void testHandleWebhookSuccess() {
        // Arrange
        Payment_Transaction__c testTransaction = PayPalTestDataFactory.createTestTransaction();
        
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/paypal/webhook/';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(PayPalTestDataFactory.createMockWebhookData());
        request.headers = new Map<String, String>{
            'PAYPAL-TRANSMISSION-SIG' => 'test-signature',
            'PAYPAL-CERT-ID' => 'test-cert-id',
            'PAYPAL-AUTH-ALGO' => 'SHA256withRSA',
            'PAYPAL-TRANSMISSION-TIME' => '2024-01-01T00:00:00Z'
        };
        
        RestResponse response = new RestResponse();
        RestContext.request = request;
        RestContext.response = response;
        
        // Act
        Test.startTest();
        PayPalWebhookHandler.handleWebhook();
        Test.stopTest();
        
        // Assert
        System.assertEquals(200, response.statusCode, 'Response should be successful');
        
        // Verify webhook log was created
        List<PayPal_Webhook_Log__c> webhookLogs = [SELECT Id, Event_Type__c, Status__c FROM PayPal_Webhook_Log__c];
        System.assertEquals(1, webhookLogs.size(), 'One webhook log should be created');
        System.assertEquals('PAYMENT.CAPTURE.COMPLETED', webhookLogs[0].Event_Type__c, 'Event type should match');
    }
    
    @IsTest
    static void testHandleWebhookInvalidSignature() {
        // Arrange
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/paypal/webhook/';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(PayPalTestDataFactory.createMockWebhookData());
        request.headers = new Map<String, String>(); // Missing required headers
        
        RestResponse response = new RestResponse();
        RestContext.request = request;
        RestContext.response = response;
        
        // Act
        Test.startTest();
        PayPalWebhookHandler.handleWebhook();
        Test.stopTest();
        
        // Assert
        System.assertEquals(401, response.statusCode, 'Response should be unauthorized');
        System.assert(response.responseBody.toString().contains('Invalid webhook signature'), 'Response should indicate invalid signature');
    }
    
    @IsTest
    static void testHandleWebhookProcessingError() {
        // Arrange - Create malformed webhook data
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/paypal/webhook/';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf('{"invalid": "json"}'); // Invalid webhook format
        request.headers = new Map<String, String>{
            'PAYPAL-TRANSMISSION-SIG' => 'test-signature',
            'PAYPAL-CERT-ID' => 'test-cert-id',
            'PAYPAL-AUTH-ALGO' => 'SHA256withRSA',
            'PAYPAL-TRANSMISSION-TIME' => '2024-01-01T00:00:00Z'
        };
        
        RestResponse response = new RestResponse();
        RestContext.request = request;
        RestContext.response = response;
        
        // Act
        Test.startTest();
        PayPalWebhookHandler.handleWebhook();
        Test.stopTest();
        
        // Assert
        System.assertEquals(500, response.statusCode, 'Response should indicate server error');
    }
    
    @IsTest
    static void testGetRecentWebhookLogs() {
        // Arrange
        PayPalTestDataFactory.createWebhookLog();
        PayPalTestDataFactory.createWebhookLog();
        
        // Act
        Test.startTest();
        List<PayPal_Webhook_Log__c> result = PayPalWebhookHandler.getRecentWebhookLogs();
        Test.stopTest();
        
        // Assert
        System.assertEquals(2, result.size(), 'Should return 2 webhook logs');
        System.assertNotEquals(null, result[0].Event_Type__c, 'Event type should not be null');
    }
    
    @IsTest
    static void testGetWebhookLogDetails() {
        // Arrange
        PayPal_Webhook_Log__c webhookLog = PayPalTestDataFactory.createWebhookLog();
        
        // Act
        Test.startTest();
        PayPal_Webhook_Log__c result = PayPalWebhookHandler.getWebhookLogDetails(webhookLog.Id);
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, result, 'Webhook log details should not be null');
        System.assertEquals(webhookLog.Id, result.Id, 'Webhook log ID should match');
        System.assertNotEquals(null, result.Webhook_Data__c, 'Webhook data should not be null');
    }
    
    @IsTest
    static void testProcessFailedWebhooks() {
        // Arrange - Create failed webhook logs
        PayPal_Webhook_Log__c failedWebhook = PayPalTestDataFactory.createWebhookLog();
        failedWebhook.Status__c = 'Failed';
        update failedWebhook;
        
        Payment_Transaction__c testTransaction = PayPalTestDataFactory.createTestTransaction();
        
        // Act
        Test.startTest();
        PayPalWebhookHandler.processFailedWebhooks();
        Test.stopTest();
        
        // Assert
        PayPal_Webhook_Log__c updatedWebhook = [SELECT Status__c FROM PayPal_Webhook_Log__c WHERE Id = :failedWebhook.Id];
        System.assertEquals('Processed', updatedWebhook.Status__c, 'Failed webhook should be processed');
    }
    
    @IsTest
    static void testValidateWebhookConfiguration() {
        // Arrange
        Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(200, '{"webhooks": []}'));
        
        // Act
        Test.startTest();
        String result = PayPalWebhookHandler.validateWebhookConfiguration();
        Test.stopTest();
        
        // Assert
        System.assert(result.contains('valid'), 'Validation should indicate configuration is valid');
    }
    
    @IsTest
    static void testValidateWebhookConfigurationFailure() {
        // Arrange
        Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(PayPalMockHttpResponseGenerator.ResponseType.ERROR_AUTHENTICATION));
        
        // Act
        Test.startTest();
        String result = PayPalWebhookHandler.validateWebhookConfiguration();
        Test.stopTest();
        
        // Assert
        System.assert(result.contains('failed'), 'Validation should indicate configuration failed');
    }
    
    @IsTest
    static void testGetWebhookStats() {
        // Arrange
        PayPalTestDataFactory.createWebhookLog();
        PayPalTestDataFactory.createWebhookLog();
        
        // Act
        Test.startTest();
        Map<String, Object> result = PayPalWebhookHandler.getWebhookStats();
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, result, 'Webhook stats should not be null');
        System.assert(result.containsKey('totalWebhooks'), 'Should contain total webhooks');
        System.assert(result.containsKey('eventTypeBreakdown'), 'Should contain event type breakdown');
        System.assert(result.containsKey('statusBreakdown'), 'Should contain status breakdown');
        
        Integer totalWebhooks = (Integer) result.get('totalWebhooks');
        System.assertEquals(2, totalWebhooks, 'Should have 2 total webhooks');
    }
    
    @IsTest
    static void testWebhookEventTypes() {
        // Test different webhook event types
        Map<String, String> eventTests = new Map<String, String>{
            'PAYMENT.CAPTURE.COMPLETED' => 'Completed',
            'PAYMENT.CAPTURE.DENIED' => 'Failed',
            'CHECKOUT.ORDER.APPROVED' => 'Approved'
        };
        
        Test.startTest();
        for (String eventType : eventTests.keySet()) {
            Payment_Transaction__c testTransaction = PayPalTestDataFactory.createTestTransaction();
            
            PaymentProcessor.processWebhookEvent(eventType, testTransaction.PayPal_Order_ID__c, new Map<String, Object>());
            
            Payment_Transaction__c updatedTransaction = [SELECT Status__c FROM Payment_Transaction__c WHERE Id = :testTransaction.Id];
            System.assertEquals(eventTests.get(eventType), updatedTransaction.Status__c, 'Status should be updated for event type: ' + eventType);
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testWebhookErrorHandling() {
        // Test webhook processing with invalid transaction ID
        Test.startTest();
        try {
            PaymentProcessor.processWebhookEvent('PAYMENT.CAPTURE.COMPLETED', 'INVALID_ORDER_ID', new Map<String, Object>());
            // Should not throw exception, but handle gracefully
        } catch (Exception e) {
            // If exception occurs, verify it's logged
            List<PayPal_Error_Log__c> errorLogs = [SELECT Id FROM PayPal_Error_Log__c];
            System.assertEquals(1, errorLogs.size(), 'Error should be logged');
        }
        Test.stopTest();
    }
}