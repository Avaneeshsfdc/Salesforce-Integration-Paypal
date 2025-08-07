public class PayPalAuthManager {
    private static final String TOKEN_ENDPOINT = '/v1/oauth2/token';
    private static final String CACHE_KEY = 'PayPalAccessToken';
    private static final Integer TOKEN_EXPIRY_BUFFER = 300; // 5 minutes buffer before expiry
    
    public class AccessTokenResponse {
        public String access_token;
        public String token_type;
        public Integer expires_in;
        public String scope;
    }
    
    public static String getAccessToken() {
        try {
            Cache.OrgPartition orgPart = Cache.Org.getPartition('local.PayPalCache');
            
            if (orgPart.contains(CACHE_KEY)) {
                Map<String, Object> cachedToken = (Map<String, Object>) orgPart.get(CACHE_KEY);
                Long expiryTime = (Long) cachedToken.get('expiry');
                
                if (System.currentTimeMillis() < expiryTime) {
                    return (String) cachedToken.get('token');
                }
            }
            
            return refreshAccessToken();
            
        } catch (Exception e) {
            System.debug('Error getting access token: ' + e.getMessage());
            return refreshAccessToken();
        }
    }
    
    public static String refreshAccessToken() {
        try {
            String requestBody = 'grant_type=client_credentials';
            
            HttpResponse response = PayPalHttpCallout.makeAuthCallout('POST', TOKEN_ENDPOINT, requestBody);
            
            if (response.getStatusCode() == 200) {
                AccessTokenResponse tokenResponse = (AccessTokenResponse) JSON.deserialize(response.getBody(), AccessTokenResponse.class);
                
                cacheAccessToken(tokenResponse.access_token, tokenResponse.expires_in);
                
                return tokenResponse.access_token;
            } else {
                Map<String, Object> errorDetails = PayPalHttpCallout.parseErrorResponse(response.getBody());
                throw new PayPalException(
                    'Failed to get PayPal access token: ' + errorDetails.get('errorMessage'), 
                    'AUTHENTICATION_ERROR',
                    response.getBody()
                );
            }
            
        } catch (PayPalException e) {
            throw e;
        } catch (Exception e) {
            PayPalException paypalEx = new PayPalException('Authentication error: ' + e.getMessage(), 'AUTHENTICATION_ERROR');
            paypalEx.logError();
            throw paypalEx;
        }
    }
    
    private static void cacheAccessToken(String token, Integer expiresIn) {
        try {
            Cache.OrgPartition orgPart = Cache.Org.getPartition('local.PayPalCache');
            
            Long expiryTime = System.currentTimeMillis() + ((expiresIn - TOKEN_EXPIRY_BUFFER) * 1000);
            
            Map<String, Object> tokenData = new Map<String, Object>{
                'token' => token,
                'expiry' => expiryTime
            };
            
            orgPart.put(CACHE_KEY, tokenData, (expiresIn - TOKEN_EXPIRY_BUFFER));
            
        } catch (Exception e) {
            System.debug('Failed to cache access token: ' + e.getMessage());
        }
    }
    
    public static Boolean validateToken(String token) {
        try {
            if (String.isBlank(token)) {
                return false;
            }
            
            HttpRequest request = new HttpRequest();
            request.setMethod('GET');
            request.setEndpoint('callout:PayPal_API/v1/identity/oauth2/userinfo');
            request.setHeader('Authorization', 'Bearer ' + token);
            request.setTimeout(30000);
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            return response.getStatusCode() == 200;
            
        } catch (Exception e) {
            System.debug('Token validation error: ' + e.getMessage());
            return false;
        }
    }
    
    public static void clearTokenCache() {
        try {
            Cache.OrgPartition orgPart = Cache.Org.getPartition('local.PayPalCache');
            orgPart.remove(CACHE_KEY);
        } catch (Exception e) {
            System.debug('Failed to clear token cache: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static Map<String, Object> getAuthStatus() {
        try {
            String token = getAccessToken();
            Boolean isValid = validateToken(token);
            
            return new Map<String, Object>{
                'isAuthenticated' => isValid,
                'hasToken' => String.isNotBlank(token)
            };
            
        } catch (Exception e) {
            return new Map<String, Object>{
                'isAuthenticated' => false,
                'hasToken' => false,
                'error' => e.getMessage()
            };
        }
    }
    
    public static PayPal_Configuration__mdt getConfiguration() {
        List<PayPal_Configuration__mdt> configs = [
            SELECT API_Base_URL__c, Environment__c 
            FROM PayPal_Configuration__mdt 
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        
        if (configs.isEmpty()) {
            throw new PayPalException('PayPal configuration not found', 'SYSTEM_ERROR');
        }
        
        return configs[0];
    }
    
    public static Boolean isSandboxEnvironment() {
        try {
            PayPal_Configuration__mdt config = getConfiguration();
            return config.Environment__c == 'Sandbox';
        } catch (Exception e) {
            System.debug('Failed to determine environment: ' + e.getMessage());
            return true; // Default to sandbox for safety
        }
    }
}