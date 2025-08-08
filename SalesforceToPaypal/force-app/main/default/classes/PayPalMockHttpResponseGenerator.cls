@IsTest
public class PayPalMockHttpResponseGenerator implements HttpCalloutMock {
    
    public enum ResponseType {
        SUCCESS_CREATE_ORDER,
        SUCCESS_CAPTURE_ORDER,
        SUCCESS_REFUND,
        SUCCESS_AUTH_TOKEN,
        ERROR_VALIDATION,
        ERROR_AUTHENTICATION,
        ERROR_SERVER,
        ERROR_NETWORK
    }
    
    private ResponseType responseType;
    private Integer statusCode;
    private String responseBody;
    
    public PayPalMockHttpResponseGenerator(ResponseType responseType) {
        this.responseType = responseType;
        setResponseData();
    }
    
    public PayPalMockHttpResponseGenerator(Integer statusCode, String responseBody) {
        this.statusCode = statusCode;
        this.responseBody = responseBody;
    }
    
    public HttpResponse respond(HttpRequest request) {
        HttpResponse response = new HttpResponse();
        
        if (statusCode != null && responseBody != null) {
            response.setStatusCode(statusCode);
            response.setBody(responseBody);
        } else {
            setResponseBasedOnType(response, request);
        }
        
        response.setHeader('Content-Type', 'application/json');
        return response;
    }
    
    private void setResponseData() {
        switch on responseType {
            when SUCCESS_CREATE_ORDER {
                this.statusCode = 201;
                this.responseBody = PayPalTestDataFactory.createMockPayPalResponse();
            }
            when SUCCESS_CAPTURE_ORDER {
                this.statusCode = 201;
                this.responseBody = PayPalTestDataFactory.createMockCaptureResponse();
            }
            when SUCCESS_REFUND {
                this.statusCode = 201;
                this.responseBody = createRefundResponse();
            }
            when SUCCESS_AUTH_TOKEN {
                this.statusCode = 200;
                this.responseBody = createAuthTokenResponse();
            }
            when ERROR_VALIDATION {
                this.statusCode = 400;
                this.responseBody = PayPalTestDataFactory.createMockErrorResponse();
            }
            when ERROR_AUTHENTICATION {
                this.statusCode = 401;
                this.responseBody = createAuthErrorResponse();
            }
            when ERROR_SERVER {
                this.statusCode = 500;
                this.responseBody = createServerErrorResponse();
            }
            when ERROR_NETWORK {
                this.statusCode = 503;
                this.responseBody = createNetworkErrorResponse();
            }
        }
    }
    
    private void setResponseBasedOnType(HttpResponse response, HttpRequest request) {
        response.setStatusCode(this.statusCode);
        response.setBody(this.responseBody);
        
        // Simulate different response times based on status code
        if (this.statusCode == 503) {
            // Simulate timeout scenario
            response.setStatusCode(503);
        }
    }
    
    private String createAuthTokenResponse() {
        return JSON.serialize(new Map<String, Object>{
            'access_token' => 'TEST_ACCESS_TOKEN_123',
            'token_type' => 'Bearer',
            'expires_in' => 32400,
            'scope' => 'https://uri.paypal.com/services/payments/payment/authcapture'
        });
    }
    
    private String createRefundResponse() {
        return JSON.serialize(new Map<String, Object>{
            'id' => 'TEST_REFUND_123',
            'status' => 'COMPLETED',
            'amount' => new Map<String, String>{
                'currency_code' => 'USD',
                'value' => '100.00'
            },
            'create_time' => '2024-01-01T00:00:00Z',
            'update_time' => '2024-01-01T00:00:01Z'
        });
    }
    
    private String createAuthErrorResponse() {
        return JSON.serialize(new Map<String, Object>{
            'error' => 'invalid_client',
            'error_description' => 'Client authentication failed'
        });
    }
    
    private String createServerErrorResponse() {
        return JSON.serialize(new Map<String, Object>{
            'name' => 'INTERNAL_SERVER_ERROR',
            'message' => 'An internal server error has occurred',
            'debug_id' => 'test-debug-id-500'
        });
    }
    
    private String createNetworkErrorResponse() {
        return JSON.serialize(new Map<String, Object>{
            'name' => 'SERVICE_UNAVAILABLE',
            'message' => 'Service temporarily unavailable',
            'debug_id' => 'test-debug-id-503'
        });
    }
    
    // Multi-response mock for testing retry logic
    public class RetryMockGenerator implements HttpCalloutMock {
        private Integer callCount = 0;
        private List<ResponseType> responses;
        
        public RetryMockGenerator(List<ResponseType> responses) {
            this.responses = responses;
        }
        
        public HttpResponse respond(HttpRequest request) {
            ResponseType currentResponse = responses[Math.min(callCount, responses.size() - 1)];
            callCount++;
            
            PayPalMockHttpResponseGenerator generator = new PayPalMockHttpResponseGenerator(currentResponse);
            return generator.respond(request);
        }
    }
}