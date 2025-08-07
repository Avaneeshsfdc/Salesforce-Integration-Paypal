@IsTest
public class PayPalServiceTest {
    
    @TestSetup
    static void setupTestData() {
        PayPalTestDataFactory.createTestAccount();
    }
    
    @IsTest
    static void testCreateOrderSuccess() {
        // Arrange
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(PayPalMockHttpResponseGenerator.ResponseType.SUCCESS_CREATE_ORDER));
        
        // Act
        Test.startTest();
        PayPalService.PayPalOrderResponse result = PayPalService.createOrder(100.00, 'USD', 'Test Payment', testAccount.Id);
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, result, 'Order response should not be null');
        System.assertEquals('TEST_ORDER_123', result.id, 'Order ID should match mock response');
        System.assertEquals('CREATED', result.status, 'Order status should be CREATED');
        
        // Verify transaction was created
        List<Payment_Transaction__c> transactions = [SELECT Id, PayPal_Order_ID__c, Amount__c, Status__c FROM Payment_Transaction__c];
        System.assertEquals(1, transactions.size(), 'One transaction should be created');
        System.assertEquals('TEST_ORDER_123', transactions[0].PayPal_Order_ID__c, 'PayPal Order ID should match');
        System.assertEquals(100.00, transactions[0].Amount__c, 'Amount should match');
        System.assertEquals('Created', transactions[0].Status__c, 'Status should be Created');
    }
    
    @IsTest
    static void testCreateOrderFailure() {
        // Arrange
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(PayPalMockHttpResponseGenerator.ResponseType.ERROR_VALIDATION));
        
        // Act & Assert
        Test.startTest();
        try {
            PayPalService.createOrder(100.00, 'USD', 'Test Payment', testAccount.Id);
            System.assert(false, 'Exception should have been thrown');
        } catch (PayPalException e) {
            System.assertEquals('API_ERROR', e.errorCode, 'Error code should match');
            System.assert(e.getMessage().contains('Failed to create PayPal order'), 'Error message should contain expected text');
        }
        Test.stopTest();
        
        // Verify no transaction was created
        List<Payment_Transaction__c> transactions = [SELECT Id FROM Payment_Transaction__c];
        System.assertEquals(0, transactions.size(), 'No transaction should be created on failure');
    }
    
    @IsTest
    static void testCaptureOrderSuccess() {
        // Arrange
        Payment_Transaction__c testTransaction = PayPalTestDataFactory.createTestTransaction();
        Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(PayPalMockHttpResponseGenerator.ResponseType.SUCCESS_CAPTURE_ORDER));
        
        // Act
        Test.startTest();
        PayPalService.PayPalOrderResponse result = PayPalService.captureOrder(testTransaction.PayPal_Order_ID__c);
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, result, 'Capture response should not be null');
        System.assertEquals('COMPLETED', result.status, 'Order status should be COMPLETED');
        
        // Verify transaction status was updated
        Payment_Transaction__c updatedTransaction = [SELECT Status__c FROM Payment_Transaction__c WHERE Id = :testTransaction.Id];
        System.assertEquals('Completed', updatedTransaction.Status__c, 'Transaction status should be updated to Completed');
    }
    
    @IsTest
    static void testCaptureOrderFailure() {
        // Arrange
        Payment_Transaction__c testTransaction = PayPalTestDataFactory.createTestTransaction();
        Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(PayPalMockHttpResponseGenerator.ResponseType.ERROR_VALIDATION));
        
        // Act & Assert
        Test.startTest();
        try {
            PayPalService.captureOrder(testTransaction.PayPal_Order_ID__c);
            System.assert(false, 'Exception should have been thrown');
        } catch (PayPalException e) {
            System.assertEquals('API_ERROR', e.errorCode, 'Error code should match');
            System.assert(e.getMessage().contains('Failed to capture PayPal order'), 'Error message should contain expected text');
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testRefundPaymentSuccess() {
        // Arrange
        Payment_Transaction__c testTransaction = PayPalTestDataFactory.createCompletedTransaction();
        Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(PayPalMockHttpResponseGenerator.ResponseType.SUCCESS_REFUND));
        
        // Act
        Test.startTest();
        String result = PayPalService.refundPayment(testTransaction.PayPal_Order_ID__c, 50.00, 'USD');
        Test.stopTest();
        
        // Assert
        System.assertEquals('Refund successful', result, 'Refund should be successful');
        
        // Verify transaction status was updated
        Payment_Transaction__c updatedTransaction = [SELECT Status__c FROM Payment_Transaction__c WHERE Id = :testTransaction.Id];
        System.assertEquals('Partially Refunded', updatedTransaction.Status__c, 'Transaction status should be Partially Refunded');
    }
    
    @IsTest
    static void testRefundPaymentFullAmount() {
        // Arrange
        Payment_Transaction__c testTransaction = PayPalTestDataFactory.createCompletedTransaction();
        Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(PayPalMockHttpResponseGenerator.ResponseType.SUCCESS_REFUND));
        
        // Act
        Test.startTest();
        String result = PayPalService.refundPayment(testTransaction.PayPal_Order_ID__c, testTransaction.Amount__c, 'USD');
        Test.stopTest();
        
        // Assert
        System.assertEquals('Refund successful', result, 'Refund should be successful');
        
        // Verify transaction status was updated
        Payment_Transaction__c updatedTransaction = [SELECT Status__c FROM Payment_Transaction__c WHERE Id = :testTransaction.Id];
        System.assertEquals('Refunded', updatedTransaction.Status__c, 'Transaction status should be Refunded');
    }
    
    @IsTest
    static void testGetPaymentHistory() {
        // Arrange
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        PayPalTestDataFactory.createTestTransaction(testAccount.Id);
        PayPalTestDataFactory.createTestTransaction(testAccount.Id);
        
        // Act
        Test.startTest();
        List<Payment_Transaction__c> result = PayPalService.getPaymentHistory(testAccount.Id);
        Test.stopTest();
        
        // Assert
        System.assertEquals(2, result.size(), 'Should return 2 transactions');
        System.assertEquals(testAccount.Id, result[0].Account__c, 'Account should match');
        System.assertEquals(testAccount.Id, result[1].Account__c, 'Account should match');
    }
    
    @IsTest
    static void testGetPaymentStatus() {
        // Arrange
        Payment_Transaction__c testTransaction = PayPalTestDataFactory.createTestTransaction();
        
        // Act
        Test.startTest();
        Payment_Transaction__c result = PayPalService.getPaymentStatus(testTransaction.PayPal_Order_ID__c);
        Test.stopTest();
        
        // Assert
        System.assertNotEquals(null, result, 'Payment status should not be null');
        System.assertEquals(testTransaction.Id, result.Id, 'Transaction ID should match');
        System.assertEquals(testTransaction.PayPal_Order_ID__c, result.PayPal_Order_ID__c, 'PayPal Order ID should match');
    }
    
    @IsTest
    static void testValidateInputParameters() {
        // Arrange
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        // Act & Assert - Test invalid amount
        Test.startTest();
        try {
            PayPalService.createOrder(-10.00, 'USD', 'Test Payment', testAccount.Id);
            System.assert(false, 'Exception should have been thrown for negative amount');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('amount'), 'Error should be related to amount validation');
        }
        Test.stopTest();
    }
    
    @IsTest
    static void testErrorLogging() {
        // Arrange
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new PayPalMockHttpResponseGenerator(PayPalMockHttpResponseGenerator.ResponseType.ERROR_SERVER));
        
        // Act
        Test.startTest();
        try {
            PayPalService.createOrder(100.00, 'USD', 'Test Payment', testAccount.Id);
        } catch (PayPalException e) {
            // Expected exception
        }
        Test.stopTest();
        
        // Assert - Verify error was logged
        List<PayPal_Error_Log__c> errorLogs = [SELECT Id, Error_Type__c, Error_Message__c FROM PayPal_Error_Log__c];
        System.assertEquals(1, errorLogs.size(), 'One error log should be created');
        System.assertEquals('SYSTEM_ERROR', errorLogs[0].Error_Type__c, 'Error type should match');
    }
}