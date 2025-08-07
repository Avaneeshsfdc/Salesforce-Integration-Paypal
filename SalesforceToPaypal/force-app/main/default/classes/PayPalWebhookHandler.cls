@RestResource(urlMapping='/paypal/webhook/*')
global class PayPalWebhookHandler {
    
    @HttpPost
    global static void handleWebhook() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        try {
            String requestBody = req.requestBody.toString();
            Map<String, String> headers = req.headers;
            
            if (!validateWebhookSignature(requestBody, headers)) {
                res.statusCode = 401;
                res.responseBody = Blob.valueOf('{"error": "Invalid webhook signature"}');
                return;
            }
            
            Map<String, Object> webhookData = (Map<String, Object>) JSON.deserializeUntyped(requestBody);
            
            logWebhookEvent(webhookData, requestBody);
            
            String eventType = (String) webhookData.get('event_type');
            String resourceId = extractResourceId(webhookData);
            Map<String, Object> resource = (Map<String, Object>) webhookData.get('resource');
            
            PaymentProcessor.processWebhookEvent(eventType, resourceId, resource);
            
            res.statusCode = 200;
            res.responseBody = Blob.valueOf('{"status": "success"}');
            
        } catch (Exception e) {
            System.debug('Webhook processing error: ' + e.getMessage());
            
            PayPalException paypalEx = new PayPalException('Webhook processing failed: ' + e.getMessage(), 'SYSTEM_ERROR');
            paypalEx.logError();
            
            res.statusCode = 500;
            res.responseBody = Blob.valueOf('{"error": "Internal server error"}');
        }
    }
    
    private static Boolean validateWebhookSignature(String requestBody, Map<String, String> headers) {
        try {
            String signature = headers.get('PAYPAL-TRANSMISSION-SIG');
            String certId = headers.get('PAYPAL-CERT-ID');
            String authAlgo = headers.get('PAYPAL-AUTH-ALGO');
            String transmissionTime = headers.get('PAYPAL-TRANSMISSION-TIME');
            String webhookId = getWebhookId();
            
            if (String.isBlank(signature) || String.isBlank(certId) || 
                String.isBlank(authAlgo) || String.isBlank(transmissionTime) || 
                String.isBlank(webhookId)) {
                return false;
            }
            
            String expectedSignature = generateExpectedSignature(
                authAlgo, certId, transmissionTime, webhookId, requestBody
            );
            
            return signature.equals(expectedSignature);
            
        } catch (Exception e) {
            System.debug('Signature validation error: ' + e.getMessage());
            return false;
        }
    }
    
    private static String generateExpectedSignature(String authAlgo, String certId, 
                                                   String transmissionTime, String webhookId, String requestBody) {
        return 'signature_validation_not_implemented';
    }
    
    private static String getWebhookId() {
        PayPal_Configuration__mdt config = PayPalAuthManager.getConfiguration();
        return 'webhook_id_from_configuration';
    }
    
    private static String extractResourceId(Map<String, Object> webhookData) {
        try {
            Map<String, Object> resource = (Map<String, Object>) webhookData.get('resource');
            
            if (resource.containsKey('id')) {
                return (String) resource.get('id');
            }
            
            if (resource.containsKey('custom_id')) {
                return (String) resource.get('custom_id');
            }
            
            Map<String, Object> supplementaryData = (Map<String, Object>) resource.get('supplementary_data');
            if (supplementaryData != null && supplementaryData.containsKey('related_ids')) {
                Map<String, Object> relatedIds = (Map<String, Object>) supplementaryData.get('related_ids');
                if (relatedIds.containsKey('order_id')) {
                    return (String) relatedIds.get('order_id');
                }
            }
            
            return null;
            
        } catch (Exception e) {
            System.debug('Error extracting resource ID: ' + e.getMessage());
            return null;
        }
    }
    
    private static void logWebhookEvent(Map<String, Object> webhookData, String requestBody) {
        try {
            String eventType = (String) webhookData.get('event_type');
            String eventId = (String) webhookData.get('id');
            String createTime = (String) webhookData.get('create_time');
            
            PayPal_Webhook_Log__c webhookLog = new PayPal_Webhook_Log__c(
                Event_Type__c = eventType,
                Event_ID__c = eventId,
                Webhook_Data__c = requestBody,
                Processed_Date__c = System.now(),
                Status__c = 'Received'
            );
            
            insert webhookLog;
            
        } catch (Exception e) {
            System.debug('Failed to log webhook event: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static List<PayPal_Webhook_Log__c> getRecentWebhookLogs() {
        try {
            return [
                SELECT Id, Name, Event_Type__c, Event_ID__c, Status__c, 
                       Processed_Date__c, CreatedDate
                FROM PayPal_Webhook_Log__c 
                ORDER BY CreatedDate DESC 
                LIMIT 50
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving webhook logs: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static PayPal_Webhook_Log__c getWebhookLogDetails(Id logId) {
        try {
            return [
                SELECT Id, Name, Event_Type__c, Event_ID__c, Webhook_Data__c,
                       Status__c, Processed_Date__c, Error_Message__c, CreatedDate
                FROM PayPal_Webhook_Log__c 
                WHERE Id = :logId
                LIMIT 1
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving webhook log details: ' + e.getMessage());
        }
    }
    
    public static void processFailedWebhooks() {
        List<PayPal_Webhook_Log__c> failedWebhooks = [
            SELECT Id, Name, Event_Type__c, Event_ID__c, Webhook_Data__c, Status__c
            FROM PayPal_Webhook_Log__c 
            WHERE Status__c = 'Failed' 
            AND CreatedDate = LAST_N_DAYS:7
            LIMIT 100
        ];
        
        for (PayPal_Webhook_Log__c webhookLog : failedWebhooks) {
            try {
                Map<String, Object> webhookData = (Map<String, Object>) JSON.deserializeUntyped(webhookLog.Webhook_Data__c);
                String resourceId = extractResourceId(webhookData);
                Map<String, Object> resource = (Map<String, Object>) webhookData.get('resource');
                
                PaymentProcessor.processWebhookEvent(webhookLog.Event_Type__c, resourceId, resource);
                
                webhookLog.Status__c = 'Processed';
                webhookLog.Error_Message__c = null;
                
            } catch (Exception e) {
                webhookLog.Status__c = 'Failed';
                webhookLog.Error_Message__c = e.getMessage();
            }
        }
        
        if (!failedWebhooks.isEmpty()) {
            update failedWebhooks;
        }
    }
    
    @AuraEnabled
    public static String validateWebhookConfiguration() {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('callout:PayPal_API/v1/notifications/webhooks');
            req.setMethod('GET');
            req.setHeader('Content-Type', 'application/json');
            req.setHeader('Accept', 'application/json');
            
            String accessToken = PayPalAuthManager.getAccessToken();
            req.setHeader('Authorization', 'Bearer ' + accessToken);
            
            Http http = new Http();
            HttpResponse response = http.send(req);
            
            if (response.getStatusCode() == 200) {
                return 'Webhook configuration is valid';
            } else {
                return 'Webhook configuration validation failed: ' + response.getBody();
            }
            
        } catch (Exception e) {
            return 'Error validating webhook configuration: ' + e.getMessage();
        }
    }
    
    @AuraEnabled
    public static Map<String, Object> getWebhookStats() {
        try {
            List<AggregateResult> stats = [
                SELECT COUNT(Id) totalCount, 
                       Event_Type__c eventType,
                       Status__c status
                FROM PayPal_Webhook_Log__c 
                WHERE CreatedDate = LAST_N_DAYS:30
                GROUP BY Event_Type__c, Status__c
            ];
            
            Map<String, Object> result = new Map<String, Object>{
                'totalWebhooks' => 0,
                'eventTypeBreakdown' => new Map<String, Object>(),
                'statusBreakdown' => new Map<String, Object>()
            };
            
            Integer totalCount = 0;
            Map<String, Object> eventTypeBreakdown = new Map<String, Object>();
            Map<String, Object> statusBreakdown = new Map<String, Object>();
            
            for (AggregateResult ar : stats) {
                Integer count = (Integer) ar.get('totalCount');
                String eventType = (String) ar.get('eventType');
                String status = (String) ar.get('status');
                
                totalCount += count;
                
                if (!eventTypeBreakdown.containsKey(eventType)) {
                    eventTypeBreakdown.put(eventType, 0);
                }
                eventTypeBreakdown.put(eventType, (Integer) eventTypeBreakdown.get(eventType) + count);
                
                if (!statusBreakdown.containsKey(status)) {
                    statusBreakdown.put(status, 0);
                }
                statusBreakdown.put(status, (Integer) statusBreakdown.get(status) + count);
            }
            
            result.put('totalWebhooks', totalCount);
            result.put('eventTypeBreakdown', eventTypeBreakdown);
            result.put('statusBreakdown', statusBreakdown);
            
            return result;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving webhook statistics: ' + e.getMessage());
        }
    }
}