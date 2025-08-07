public class PayPalHttpCallout {
    private static final Integer TIMEOUT_SECONDS = 120000;
    private static final String NAMED_CREDENTIAL = 'PayPal_API';
    
    public static HttpResponse makeCallout(String method, String endpoint, String body) {
        return makeCallout(method, endpoint, body, new Map<String, String>());
    }
    
    public static HttpResponse makeCallout(String method, String endpoint, String body, Map<String, String> additionalHeaders) {
        try {
            HttpRequest request = new HttpRequest();
            request.setMethod(method);
            request.setTimeout(TIMEOUT_SECONDS);
            
            String fullEndpoint = 'callout:' + NAMED_CREDENTIAL + endpoint;
            request.setEndpoint(fullEndpoint);
            
            request.setHeader('Content-Type', 'application/json');
            request.setHeader('Accept', 'application/json');
            request.setHeader('PayPal-Request-Id', generateRequestId());
            
            String accessToken = PayPalAuthManager.getAccessToken();
            if (String.isNotBlank(accessToken)) {
                request.setHeader('Authorization', 'Bearer ' + accessToken);
            }
            
            for (String headerName : additionalHeaders.keySet()) {
                request.setHeader(headerName, additionalHeaders.get(headerName));
            }
            
            if (String.isNotBlank(body) && (method == 'POST' || method == 'PUT' || method == 'PATCH')) {
                request.setBody(body);
            }
            
            System.debug('PayPal Request: ' + method + ' ' + fullEndpoint);
            System.debug('PayPal Request Body: ' + body);
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            System.debug('PayPal Response Status: ' + response.getStatusCode());
            System.debug('PayPal Response Body: ' + response.getBody());
            
            if (response.getStatusCode() == 401) {
                PayPalAuthManager.refreshAccessToken();
                accessToken = PayPalAuthManager.getAccessToken();
                request.setHeader('Authorization', 'Bearer ' + accessToken);
                response = http.send(request);
            }
            
            return response;
            
        } catch (Exception e) {
            PayPalException paypalEx = new PayPalException('HTTP Callout failed: ' + e.getMessage(), 'NETWORK_ERROR');
            paypalEx.logError();
            throw paypalEx;
        }
    }
    
    public static HttpResponse makeAuthCallout(String method, String endpoint, String body) {
        try {
            HttpRequest request = new HttpRequest();
            request.setMethod(method);
            request.setTimeout(TIMEOUT_SECONDS);
            
            String fullEndpoint = 'callout:' + NAMED_CREDENTIAL + endpoint;
            request.setEndpoint(fullEndpoint);
            
            request.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            request.setHeader('Accept', 'application/json');
            
            if (String.isNotBlank(body)) {
                request.setBody(body);
            }
            
            System.debug('PayPal Auth Request: ' + method + ' ' + fullEndpoint);
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            System.debug('PayPal Auth Response Status: ' + response.getStatusCode());
            
            return response;
            
        } catch (Exception e) {
            PayPalException paypalEx = new PayPalException('Auth Callout failed: ' + e.getMessage(), 'AUTHENTICATION_ERROR');
            paypalEx.logError();
            throw paypalEx;
        }
    }
    
    private static String generateRequestId() {
        String chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz';
        String requestId = '';
        
        for (Integer i = 0; i < 32; i++) {
            Integer randomIndex = Math.mod(Math.abs(Crypto.getRandomInteger()), chars.length());
            requestId += chars.substring(randomIndex, randomIndex + 1);
        }
        
        return requestId;
    }
    
    public static Map<String, Object> parseErrorResponse(String responseBody) {
        try {
            Map<String, Object> errorResponse = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            Map<String, Object> parsedError = new Map<String, Object>();
            
            if (errorResponse.containsKey('name')) {
                parsedError.put('errorCode', errorResponse.get('name'));
            }
            
            if (errorResponse.containsKey('message')) {
                parsedError.put('errorMessage', errorResponse.get('message'));
            }
            
            if (errorResponse.containsKey('details')) {
                parsedError.put('errorDetails', errorResponse.get('details'));
            }
            
            return parsedError;
            
        } catch (Exception e) {
            return new Map<String, Object>{
                'errorCode' => 'PARSE_ERROR',
                'errorMessage' => 'Failed to parse PayPal error response',
                'errorDetails' => responseBody
            };
        }
    }
    
    public static Boolean isRetryableError(Integer statusCode) {
        Set<Integer> retryableCodes = new Set<Integer>{ 500, 502, 503, 504, 429 };
        return retryableCodes.contains(statusCode);
    }
    
    public static HttpResponse makeCalloutWithRetry(String method, String endpoint, String body, Integer maxRetries) {
        HttpResponse response;
        Integer attempts = 0;
        
        do {
            attempts++;
            response = makeCallout(method, endpoint, body);
            
            if (!isRetryableError(response.getStatusCode()) || attempts >= maxRetries) {
                break;
            }
            
            Integer delay = attempts * 1000;
            System.debug('Retrying PayPal request in ' + delay + ' ms. Attempt ' + attempts + ' of ' + maxRetries);
            
        } while (attempts < maxRetries);
        
        return response;
    }
}