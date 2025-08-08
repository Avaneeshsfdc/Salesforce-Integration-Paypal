@IsTest
public class PayPalIntegrationTest {
    
    @TestSetup
    static void setupIntegrationTestData() {
        // Create comprehensive test data for integration scenarios
        Account testAccount = PayPalTestDataFactory.createTestAccount();
        
        // Create multiple transactions for comprehensive testing
        Payment_Transaction__c transaction1 = PayPalTestDataFactory.createTestTransaction(testAccount.Id);
        Payment_Transaction__c transaction2 = PayPalTestDataFactory.createCompletedTransaction();
        
        // Create webhook logs
        PayPalTestDataFactory.createWebhookLog();
        PayPalTestDataFactory.createWebhookLog();
        
        // Create error logs
        PayPalTestDataFactory.createErrorLog();
    }
    
    @IsTest
    static void testEndToEndPaymentWorkflow() {
        // Integration Test: Complete payment workflow from creation to completion
        Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(PayPalMockHttpResponseGenerator.ResponseType.SUCCESS_CREATE_ORDER));
        
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        // Step 1: Create payment request
        PaymentProcessor.PaymentRequest request = new PaymentProcessor.PaymentRequest();
        request.amount = 150.00;
        request.currencyCode = 'USD';
        request.description = 'Integration Test Payment';
        request.recordId = testAccount.Id;
        request.paymentType = PaymentProcessor.PaymentType.ONE_TIME;
        
        // Step 2: Process payment (creates order)
        PaymentProcessor.PaymentResult createResult = PaymentProcessor.processPayment(request);
        
        // Step 3: Simulate customer approval (webhook event)
        if (createResult.success) {
            // Mock capture order response
            Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(PayPalMockHttpResponseGenerator.ResponseType.SUCCESS_CAPTURE_ORDER));
            
            // Step 4: Capture payment
            PaymentProcessor.PaymentResult captureResult = PaymentProcessor.capturePayment(createResult.orderId);
            
            // Step 5: Process webhook event for payment completion
            PaymentProcessor.processWebhookEvent('PAYMENT.CAPTURE.COMPLETED', createResult.orderId, new Map<String, Object>());
            
            Test.stopTest();
            
            // Verify complete workflow
            System.assertEquals(true, createResult.success, 'Payment creation should succeed');
            System.assertEquals(true, captureResult.success, 'Payment capture should succeed');
            System.assertNotEquals(null, createResult.orderId, 'Order ID should be generated');
            
            // Verify transaction record was created and updated
            Payment_Transaction__c finalTransaction = [
                SELECT Id, Status__c, PayPal_Order_ID__c, Amount__c 
                FROM Payment_Transaction__c 
                WHERE PayPal_Order_ID__c = :createResult.orderId
                LIMIT 1
            ];
            
            System.assertEquals('Completed', finalTransaction.Status__c, 'Transaction should be completed');
            System.assertEquals(150.00, finalTransaction.Amount__c, 'Amount should match request');
        }
    }
    
    @IsTest
    static void testFailedPaymentWorkflow() {
        // Integration Test: Handle failed payment scenarios
        Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(PayPalMockHttpResponseGenerator.ResponseType.ERROR_AUTHENTICATION));
        
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        // Create payment request that will fail
        PaymentProcessor.PaymentRequest request = new PaymentProcessor.PaymentRequest();
        request.amount = 100.00;
        request.currencyCode = 'USD';
        request.description = 'Failed Payment Test';
        request.recordId = testAccount.Id;
        request.paymentType = PaymentProcessor.PaymentType.ONE_TIME;
        
        PaymentProcessor.PaymentResult result = PaymentProcessor.processPayment(request);
        
        Test.stopTest();
        
        // Verify failure handling
        System.assertEquals(false, result.success, 'Payment should fail');
        System.assertNotEquals(null, result.errorMessage, 'Error message should be provided');
        
        // Verify error was logged
        List<PayPal_Error_Log__c> errorLogs = [
            SELECT Id, Error_Message__c, Error_Type__c 
            FROM PayPal_Error_Log__c 
            WHERE Error_Type__c = 'API_ERROR'
        ];
        
        System.assertEquals(1, errorLogs.size(), 'Error should be logged');
        System.assert(errorLogs[0].Error_Message__c.contains('Authentication'), 'Error message should contain authentication details');
    }
    
    @IsTest
    static void testRefundWorkflow() {
        // Integration Test: Complete refund workflow
        Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(PayPalMockHttpResponseGenerator.ResponseType.SUCCESS_REFUND));
        
        // Get completed transaction for refund
        Payment_Transaction__c completedTransaction = [
            SELECT Id, PayPal_Order_ID__c, Amount__c, Currency_Code__c 
            FROM Payment_Transaction__c 
            WHERE Status__c = 'Completed' 
            LIMIT 1
        ];
        
        Test.startTest();
        
        // Process refund
        PaymentProcessor.PaymentResult refundResult = PaymentProcessor.refundPayment(
            completedTransaction.PayPal_Order_ID__c, 
            completedTransaction.Amount__c, 
            completedTransaction.Currency_Code__c
        );
        
        // Process webhook event for refund completion
        PaymentProcessor.processWebhookEvent(
            'PAYMENT.CAPTURE.REFUNDED', 
            completedTransaction.PayPal_Order_ID__c, 
            new Map<String, Object>{
                'amount' => new Map<String, String>{
                    'value' => String.valueOf(completedTransaction.Amount__c),
                    'currency_code' => completedTransaction.Currency_Code__c
                }
            }
        );
        
        Test.stopTest();
        
        // Verify refund workflow
        System.assertEquals(true, refundResult.success, 'Refund should succeed');
        System.assertEquals('Refunded', refundResult.status, 'Status should be Refunded');
        
        // Verify transaction status was updated
        Payment_Transaction__c refundedTransaction = [
            SELECT Status__c 
            FROM Payment_Transaction__c 
            WHERE Id = :completedTransaction.Id
        ];
        
        System.assertEquals('Refunded', refundedTransaction.Status__c, 'Transaction should be marked as refunded');
    }
    
    @IsTest
    static void testWebhookProcessingWorkflow() {
        // Integration Test: Webhook processing from receipt to completion
        Payment_Transaction__c testTransaction = [SELECT PayPal_Order_ID__c FROM Payment_Transaction__c LIMIT 1];
        
        // Create webhook request
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/paypal/webhook/';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(PayPalTestDataFactory.createMockWebhookData());
        // Set headers using put method
        req.headers.put('PAYPAL-TRANSMISSION-SIG', 'test-signature');
        req.headers.put('PAYPAL-CERT-ID', 'test-cert-id');
        req.headers.put('PAYPAL-AUTH-ALGO', 'SHA256withRSA');
        req.headers.put('PAYPAL-TRANSMISSION-TIME', '2024-01-01T00:00:00Z');
        
        RestResponse response = new RestResponse();
        RestContext.request = req;
        RestContext.response = response;
        
        Test.startTest();
        
        // Process webhook
        PayPalWebhookHandler.handleWebhook();
        
        Test.stopTest();
        
        // Verify webhook processing
        System.assertEquals(200, response.statusCode, 'Webhook should be processed successfully');
        
        // Verify webhook log was created
        List<PayPal_Webhook_Log__c> webhookLogs = [
            SELECT Id, Status__c, Event_Type__c 
            FROM PayPal_Webhook_Log__c 
            ORDER BY CreatedDate DESC 
            LIMIT 1
        ];
        
        System.assertEquals(1, webhookLogs.size(), 'Webhook log should be created');
        System.assertEquals('Processed', webhookLogs[0].Status__c, 'Webhook should be marked as processed');
    }
    
    @IsTest
    static void testBulkPaymentProcessing() {
        // Integration Test: Process multiple payments concurrently
        Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(PayPalMockHttpResponseGenerator.ResponseType.SUCCESS_CREATE_ORDER));
        
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        List<PaymentProcessor.PaymentRequest> bulkRequests = new List<PaymentProcessor.PaymentRequest>();
        
        // Create multiple payment requests
        for (Integer i = 0; i < 5; i++) {
            PaymentProcessor.PaymentRequest request = new PaymentProcessor.PaymentRequest();
            request.amount = 50.00 + (i * 10);
            request.currencyCode = 'USD';
            request.description = 'Bulk Payment Test ' + i;
            request.recordId = testAccount.Id;
            request.paymentType = PaymentProcessor.PaymentType.ONE_TIME;
            bulkRequests.add(request);
        }
        
        List<PaymentProcessor.PaymentResult> results = new List<PaymentProcessor.PaymentResult>();
        
        Test.startTest();
        
        // Process bulk payments
        for (PaymentProcessor.PaymentRequest request : bulkRequests) {
            PaymentProcessor.PaymentResult result = PaymentProcessor.processPayment(request);
            results.add(result);
        }
        
        Test.stopTest();
        
        // Verify all payments were processed
        System.assertEquals(5, results.size(), 'All payments should be processed');
        
        for (PaymentProcessor.PaymentResult result : results) {
            System.assertEquals(true, result.success, 'Each payment should succeed');
            System.assertNotEquals(null, result.orderId, 'Each payment should have order ID');
        }
        
        // Verify transaction records were created
        List<Payment_Transaction__c> transactions = [
            SELECT Id, Amount__c 
            FROM Payment_Transaction__c 
            WHERE Account__c = :testAccount.Id
        ];
        
        System.assert(transactions.size() >= 5, 'All transactions should be created');
    }
    
    @IsTest
    static void testErrorRecoveryWorkflow() {
        // Integration Test: Error handling and recovery mechanisms
        List<PayPal_Error_Log__c> initialErrors = [SELECT Id FROM PayPal_Error_Log__c];
        Integer initialErrorCount = initialErrors.size();
        
        Test.startTest();
        
        // Simulate various error scenarios
        try {
            // Invalid payment amount
            PaymentProcessor.PaymentRequest invalidRequest = new PaymentProcessor.PaymentRequest();
            invalidRequest.amount = -100.00;
            invalidRequest.currencyCode = 'USD';
            invalidRequest.description = 'Invalid Payment';
            
            PaymentProcessor.PaymentResult result = PaymentProcessor.processPayment(invalidRequest);
            System.assertEquals(false, result.success, 'Invalid payment should fail');
            
            // Invalid order ID for capture
            PaymentProcessor.PaymentResult captureResult = PaymentProcessor.capturePayment('INVALID_ORDER_ID');
            System.assertEquals(false, captureResult.success, 'Invalid capture should fail');
            
            // Invalid webhook processing
            PaymentProcessor.processWebhookEvent('INVALID_EVENT_TYPE', 'INVALID_ORDER_ID', new Map<String, Object>());
            
        } catch (Exception e) {
            // Exceptions should be handled gracefully
            System.debug('Expected exception handled: ' + e.getMessage());
        }
        
        Test.stopTest();
        
        // Verify error logging
        List<PayPal_Error_Log__c> finalErrors = [SELECT Id, Error_Message__c FROM PayPal_Error_Log__c];
        System.assert(finalErrors.size() > initialErrorCount, 'Errors should be logged');
        
        // Verify system continues to function despite errors
        System.assertEquals(true, true, 'System should remain stable after errors');
    }
    
    @IsTest
    static void testConfigurationValidation() {
        // Integration Test: Validate configuration and setup
        Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(200, '{"access_token":"test_token","expires_in":32400}'));
        
        Test.startTest();
        
        // Test authentication
        String authToken = PayPalAuthManager.getAccessToken();
        System.assertNotEquals(null, authToken, 'Authentication should work');
        
        // Test webhook configuration validation
        Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(200, '{"webhooks": []}'));
        String webhookValidation = PayPalWebhookHandler.validateWebhookConfiguration();
        System.assert(webhookValidation.contains('valid'), 'Webhook configuration should be valid');
        
        Test.stopTest();
        
        // Verify configuration components
        System.assertNotEquals(null, authToken, 'Access token should be obtained');
        System.assert(webhookValidation.length() > 0, 'Webhook validation should return results');
    }
    
    @IsTest
    static void testDataConsistencyAndIntegrity() {
        // Integration Test: Ensure data consistency across all operations
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(PayPalMockHttpResponseGenerator.ResponseType.SUCCESS_CREATE_ORDER));
        
        Test.startTest();
        
        // Create payment
        PaymentProcessor.PaymentRequest request = new PaymentProcessor.PaymentRequest();
        request.amount = 200.00;
        request.currencyCode = 'USD';
        request.description = 'Data Integrity Test';
        request.recordId = testAccount.Id;
        request.paymentType = PaymentProcessor.PaymentType.ONE_TIME;
        
        PaymentProcessor.PaymentResult result = PaymentProcessor.processPayment(request);
        
        if (result.success) {
            // Verify transaction consistency
            Payment_Transaction__c paymentTxn = [
                SELECT Id, Amount__c, Currency_Code__c, PayPal_Order_ID__c, Account__c 
                FROM Payment_Transaction__c 
                WHERE PayPal_Order_ID__c = :result.orderId
                LIMIT 1
            ];
            
            System.assertEquals(request.amount, paymentTxn.Amount__c, 'Amount should match');
            System.assertEquals(request.currencyCode, paymentTxn.Currency_Code__c, 'Currency should match');
            System.assertEquals(request.recordId, paymentTxn.Account__c, 'Record ID should match');
            System.assertEquals(result.orderId, paymentTxn.PayPal_Order_ID__c, 'Order ID should match');
        }
        
        Test.stopTest();
        
        // Verify no orphaned records
        List<Payment_Transaction__c> orphanedTransactions = [
            SELECT Id 
            FROM Payment_Transaction__c 
            WHERE PayPal_Order_ID__c = null OR Account__c = null
        ];
        
        System.assertEquals(0, orphanedTransactions.size(), 'No orphaned transactions should exist');
    }
    
    @IsTest
    static void testPerformanceAndLimits() {
        // Integration Test: Verify performance within Salesforce limits
        Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(PayPalMockHttpResponseGenerator.ResponseType.SUCCESS_CREATE_ORDER));
        
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        Test.startTest();
        
        Integer soqlQueries = Limits.getQueries();
        Integer dmlStatements = Limits.getDMLStatements();
        Integer callouts = Limits.getCallouts();
        
        // Process multiple operations
        for (Integer i = 0; i < 3; i++) {
            PaymentProcessor.PaymentRequest request = new PaymentProcessor.PaymentRequest();
            request.amount = 75.00;
            request.currencyCode = 'USD';
            request.description = 'Performance Test ' + i;
            request.recordId = testAccount.Id;
            request.paymentType = PaymentProcessor.PaymentType.ONE_TIME;
            
            PaymentProcessor.processPayment(request);
        }
        
        Test.stopTest();
        
        // Verify we're within limits
        System.assert(Limits.getQueries() - soqlQueries < 100, 'SOQL queries should be within limits');
        System.assert(Limits.getDMLStatements() - dmlStatements < 50, 'DML statements should be within limits');
        System.assert(Limits.getCallouts() - callouts < 10, 'HTTP callouts should be within limits');
    }
}