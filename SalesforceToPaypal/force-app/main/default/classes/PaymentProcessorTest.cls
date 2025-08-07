@IsTest
public class PaymentProcessorTest {
    
    @TestSetup
    static void setupTestData() {
        PayPalTestDataFactory.createTestAccount();
    }
    
    @IsTest
    static void testProcessOneTimePaymentSuccess() {
        // Arrange
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(PayPalMockHttpResponseGenerator.ResponseType.SUCCESS_CREATE_ORDER));
        
        PaymentProcessor.PaymentRequest request = new PaymentProcessor.PaymentRequest();
        request.amount = 100.00;
        request.currencyCode = 'USD';
        request.description = 'Test Payment';
        request.recordId = testAccount.Id;
        request.paymentType = PaymentProcessor.PaymentType.ONE_TIME;
        
        // Act
        Test.startTest();
        PaymentProcessor.PaymentResult result = PaymentProcessor.processPayment(request);
        Test.stopTest();
        
        // Assert
        System.assertEquals(true, result.success, 'Payment should be successful');
        System.assertNotEquals(null, result.orderId, 'Order ID should not be null');
        System.assertEquals('CREATED', result.status, 'Status should be CREATED');
        System.assertNotEquals(null, result.approvalUrl, 'Approval URL should not be null');
        
        // Verify transaction was created
        List<Payment_Transaction__c> transactions = [SELECT Id, PayPal_Order_ID__c FROM Payment_Transaction__c];
        System.assertEquals(1, transactions.size(), 'One transaction should be created');
    }
    
    @IsTest
    static void testProcessPaymentValidationErrors() {
        // Test invalid amount
        PaymentProcessor.PaymentRequest request = new PaymentProcessor.PaymentRequest();
        request.amount = -10.00; // Invalid negative amount
        request.currencyCode = 'USD';
        request.description = 'Test Payment';
        
        Test.startTest();
        PaymentProcessor.PaymentResult result = PaymentProcessor.processPayment(request);
        Test.stopTest();
        
        System.assertEquals(false, result.success, 'Payment should fail');
        System.assert(result.errorMessage.contains('amount'), 'Error should be related to amount');
    }
    
    @IsTest
    static void testProcessPaymentInvalidCurrency() {
        // Arrange
        PaymentProcessor.PaymentRequest request = new PaymentProcessor.PaymentRequest();
        request.amount = 100.00;
        request.currencyCode = 'INVALID'; // Unsupported currency
        request.description = 'Test Payment';
        
        // Act
        Test.startTest();
        PaymentProcessor.PaymentResult result = PaymentProcessor.processPayment(request);
        Test.stopTest();
        
        // Assert
        System.assertEquals(false, result.success, 'Payment should fail');
        System.assert(result.errorMessage.contains('currency'), 'Error should be related to currency');
    }
    
    @IsTest
    static void testCapturePaymentSuccess() {
        // Arrange
        Payment_Transaction__c testTransaction = PayPalTestDataFactory.createTestTransaction();
        Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(PayPalMockHttpResponseGenerator.ResponseType.SUCCESS_CAPTURE_ORDER));
        
        // Act
        Test.startTest();
        PaymentProcessor.PaymentResult result = PaymentProcessor.capturePayment(testTransaction.PayPal_Order_ID__c);
        Test.stopTest();
        
        // Assert
        System.assertEquals(true, result.success, 'Capture should be successful');
        System.assertNotEquals(null, result.paymentTransaction, 'Payment transaction should not be null');
    }
    
    @IsTest
    static void testRefundPaymentSuccess() {
        // Arrange
        Payment_Transaction__c testTransaction = PayPalTestDataFactory.createCompletedTransaction();
        Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(PayPalMockHttpResponseGenerator.ResponseType.SUCCESS_REFUND));
        
        // Act
        Test.startTest();
        PaymentProcessor.PaymentResult result = PaymentProcessor.refundPayment(testTransaction.PayPal_Order_ID__c, 50.00, 'USD');
        Test.stopTest();
        
        // Assert
        System.assertEquals(true, result.success, 'Refund should be successful');
        System.assertEquals('Refunded', result.status, 'Status should be Refunded');
    }
    
    @IsTest
    static void testProcessRecurringPaymentNotImplemented() {
        // Arrange
        PaymentProcessor.PaymentRequest request = new PaymentProcessor.PaymentRequest();
        request.amount = 100.00;
        request.currencyCode = 'USD';
        request.description = 'Test Payment';
        request.paymentType = PaymentProcessor.PaymentType.RECURRING;
        
        // Act
        Test.startTest();
        PaymentProcessor.PaymentResult result = PaymentProcessor.processPayment(request);
        Test.stopTest();
        
        // Assert
        System.assertEquals(false, result.success, 'Recurring payment should fail as not implemented');
        System.assert(result.errorMessage.contains('not yet implemented'), 'Error should indicate not implemented');
    }
    
    @IsTest
    static void testProcessQuickPayment() {
        // Arrange
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(PayPalMockHttpResponseGenerator.ResponseType.SUCCESS_CREATE_ORDER));
        
        // Act
        Test.startTest();
        PaymentProcessor.PaymentResult result = PaymentProcessor.processQuickPayment(100.00, 'USD', 'Quick Test Payment', testAccount.Id);
        Test.stopTest();
        
        // Assert
        System.assertEquals(true, result.success, 'Quick payment should be successful');
        System.assertNotEquals(null, result.orderId, 'Order ID should not be null');
    }
    
    @IsTest
    static void testCaptureQuickPayment() {
        // Arrange
        Payment_Transaction__c testTransaction = PayPalTestDataFactory.createTestTransaction();
        Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(PayPalMockHttpResponseGenerator.ResponseType.SUCCESS_CAPTURE_ORDER));
        
        // Act
        Test.startTest();
        PaymentProcessor.PaymentResult result = PaymentProcessor.captureQuickPayment(testTransaction.PayPal_Order_ID__c);
        Test.stopTest();
        
        // Assert
        System.assertEquals(true, result.success, 'Quick capture should be successful');
    }
    
    @IsTest
    static void testProcessRefund() {
        // Arrange
        Payment_Transaction__c testTransaction = PayPalTestDataFactory.createCompletedTransaction();
        Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(PayPalMockHttpResponseGenerator.ResponseType.SUCCESS_REFUND));
        
        // Act
        Test.startTest();
        PaymentProcessor.PaymentResult result = PaymentProcessor.processRefund(testTransaction.PayPal_Order_ID__c, 25.00, 'USD');
        Test.stopTest();
        
        // Assert
        System.assertEquals(true, result.success, 'Refund should be successful');
    }
    
    @IsTest
    static void testWebhookEventProcessingPaymentCompleted() {
        // Arrange
        Payment_Transaction__c testTransaction = PayPalTestDataFactory.createTestTransaction();
        Map<String, Object> eventData = new Map<String, Object>();
        
        // Act
        Test.startTest();
        PaymentProcessor.processWebhookEvent('PAYMENT.CAPTURE.COMPLETED', testTransaction.PayPal_Order_ID__c, eventData);
        Test.stopTest();
        
        // Assert
        Payment_Transaction__c updatedTransaction = [SELECT Status__c FROM Payment_Transaction__c WHERE Id = :testTransaction.Id];
        System.assertEquals('Completed', updatedTransaction.Status__c, 'Status should be updated to Completed');
    }
    
    @IsTest
    static void testWebhookEventProcessingPaymentDenied() {
        // Arrange
        Payment_Transaction__c testTransaction = PayPalTestDataFactory.createTestTransaction();
        Map<String, Object> eventData = new Map<String, Object>();
        
        // Act
        Test.startTest();
        PaymentProcessor.processWebhookEvent('PAYMENT.CAPTURE.DENIED', testTransaction.PayPal_Order_ID__c, eventData);
        Test.stopTest();
        
        // Assert
        Payment_Transaction__c updatedTransaction = [SELECT Status__c FROM Payment_Transaction__c WHERE Id = :testTransaction.Id];
        System.assertEquals('Failed', updatedTransaction.Status__c, 'Status should be updated to Failed');
    }
    
    @IsTest
    static void testWebhookEventProcessingPaymentRefunded() {
        // Arrange
        Payment_Transaction__c testTransaction = PayPalTestDataFactory.createCompletedTransaction();
        Map<String, Object> eventData = new Map<String, Object>{
            'amount' => new Map<String, String>{
                'value' => '50.00',
                'currency_code' => 'USD'
            }
        };
        
        // Act
        Test.startTest();
        PaymentProcessor.processWebhookEvent('PAYMENT.CAPTURE.REFUNDED', testTransaction.PayPal_Order_ID__c, eventData);
        Test.stopTest();
        
        // Assert
        Payment_Transaction__c updatedTransaction = [SELECT Status__c FROM Payment_Transaction__c WHERE Id = :testTransaction.Id];
        System.assertEquals('Partially Refunded', updatedTransaction.Status__c, 'Status should be updated to Partially Refunded');
    }
    
    @IsTest
    static void testGetPaymentStats() {
        // Arrange
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        PayPalTestDataFactory.createTestTransaction(testAccount.Id);
        PayPalTestDataFactory.createCompletedTransaction();
        
        // Act
        Test.startTest();
        Map<String, Object> result = PaymentProcessor.getPaymentStats(testAccount.Id);
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, result, 'Payment stats should not be null');
        System.assert(result.containsKey('totalTransactions'), 'Should contain total transactions');
        System.assert(result.containsKey('totalAmount'), 'Should contain total amount');
        System.assert(result.containsKey('statusBreakdown'), 'Should contain status breakdown');
        
        Integer totalTransactions = (Integer) result.get('totalTransactions');
        System.assert(totalTransactions >= 1, 'Should have at least 1 transaction for the account');
    }
    
    @IsTest
    static void testExceptionHandling() {
        // Arrange
        Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(PayPalMockHttpResponseGenerator.ResponseType.ERROR_SERVER));
        
        PaymentProcessor.PaymentRequest request = new PaymentProcessor.PaymentRequest();
        request.amount = 100.00;
        request.currencyCode = 'USD';
        request.description = 'Test Payment';
        
        // Act
        Test.startTest();
        PaymentProcessor.PaymentResult result = PaymentProcessor.processPayment(request);
        Test.stopTest();
        
        // Assert
        System.assertEquals(false, result.success, 'Payment should fail');
        System.assertNotEquals(null, result.errorMessage, 'Error message should not be null');
        
        // Verify error was logged
        List<PayPal_Error_Log__c> errorLogs = [SELECT Id FROM PayPal_Error_Log__c];
        System.assertEquals(1, errorLogs.size(), 'One error log should be created');
    }
}