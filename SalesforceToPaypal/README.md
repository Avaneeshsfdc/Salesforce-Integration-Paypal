# Salesforce PayPal Integration

A comprehensive Salesforce application that integrates with PayPal for secure payment processing. This integration provides a complete payment solution with advanced Lightning Web Components, robust error handling, and configurable settings.

## Features

### Payment Processing
- **Multiple Payment Methods**: Credit Card, PayPal Balance, Bank Transfer
- **Real-time Payment Status**: Live updates on payment processing
- **Refund Processing**: Full and partial refund capabilities
- **Multi-currency Support**: USD, EUR, GBP, CAD, AUD, JPY
- **Payment Authorization & Capture**: Two-step payment workflow

### User Experience
- **Lightning Web Components**: Modern, responsive payment forms
- **Mobile Optimized**: Works seamlessly on mobile devices
- **Real-time Validation**: Client-side and server-side validation
- **Payment History**: Complete transaction tracking and history
- **Export Functionality**: CSV export of payment data

### Security & Compliance
- **Named Credentials**: Secure API credential storage
- **Custom Metadata**: Configuration without code deployment
- **Audit Trail**: Complete logging of all transactions
- **Error Handling**: Comprehensive exception management
- **Webhook Validation**: Secure webhook processing

### Administration
- **Configurable Settings**: Easy environment switching (Sandbox/Production)
- **Permission-based Access**: Role-based feature access
- **Analytics Dashboard**: Payment metrics and reporting
- **Webhook Management**: Real-time event processing

## Architecture

### Apex Classes
- `PayPalService` - Main PayPal API integration
- `PayPalHttpCallout` - HTTP request utilities with retry logic
- `PayPalAuthManager` - OAuth token management with caching
- `PaymentProcessor` - Payment orchestration and workflow
- `PayPalWebhookHandler` - Webhook event processing
- `PayPalException` - Custom exception handling with logging

### Lightning Web Components
- `paymentForm` - Payment form with PayPal integration
- `paymentStatus` - Real-time payment status tracking
- `paymentHistory` - Transaction history with filtering

### Custom Objects
- `Payment_Transaction__c` - Payment transaction records
- `PayPal_Error_Log__c` - Error logging and tracking
- `PayPal_Webhook_Log__c` - Webhook event audit trail
- `PayPal_Configuration__mdt` - Environment configuration

## Setup Instructions

### 1. PayPal Developer Account Setup
1. Create a PayPal Developer account at [developer.paypal.com](https://developer.paypal.com)
2. Create a new application in your PayPal dashboard
3. Note down your Client ID and Client Secret

### 2. Salesforce Configuration
1. Deploy this package to your Salesforce org
2. Assign the `PayPal Integration Access` permission set to users
3. Configure Named Credentials:
   - Go to Setup > Named Credentials
   - Edit `PayPal_API` credential
   - Enter your PayPal Client ID and Client Secret

### 3. Environment Configuration
1. Go to Setup > Custom Metadata Types
2. Edit `PayPal Configuration` records
3. Update API Base URL based on environment:
   - Sandbox: `https://api-m.sandbox.paypal.com`
   - Production: `https://api-m.paypal.com`

### 4. Remote Site Settings
Add these remote sites in Setup > Remote Site Settings:
- `https://api-m.sandbox.paypal.com` (for sandbox)
- `https://api-m.paypal.com` (for production)
- `https://www.paypal.com` (for PayPal JS SDK)

### 5. PayPal Webhook Setup
1. In your PayPal Developer dashboard, create a webhook endpoint
2. Use this URL: `https://yourdomain.my.salesforce.com/services/apexrest/paypal/webhook/`
3. Subscribe to these events:
   - `PAYMENT.CAPTURE.COMPLETED`
   - `PAYMENT.CAPTURE.DENIED`
   - `PAYMENT.CAPTURE.REFUNDED`
   - `CHECKOUT.ORDER.APPROVED`

### 6. Update PayPal Client ID
Edit the `paymentForm` LWC component and replace `YOUR_CLIENT_ID` with your actual PayPal Client ID:
```javascript
// In paymentForm.js, line with PayPal SDK script
script.src = 'https://www.paypal.com/sdk/js?client-id=YOUR_ACTUAL_CLIENT_ID&currency=USD,EUR,GBP,CAD,AUD,JPY';
```

## Usage

### Adding Payment Components to Pages
1. **Record Pages**: Add payment components to Account, Contact, or Opportunity pages
2. **App Pages**: Create dedicated payment processing pages
3. **Flows**: Use components in Screen Flows for guided payment processes

### Processing Payments
1. Navigate to a record page with the payment form
2. Enter payment amount, currency, and description
3. Click PayPal payment buttons to process
4. Track payment status in real-time
5. View payment history and export data

### Managing Refunds
1. Open payment status component
2. Click "Full Refund" or "Partial Refund"
3. Enter refund amount if partial
4. Process refund through PayPal

## Customization

### Adding New Payment Methods
Extend the `PaymentProcessor` class to support additional payment types:
```apex
when BANK_TRANSFER {
    result = processBankTransferPayment(request);
}
```

### Custom Fields
Add custom fields to `Payment_Transaction__c` for additional data:
- Customer information
- Product details
- Tax amounts
- Shipping information

### Workflow Automation
Create Process Builder or Flow processes triggered by payment status changes:
- Send confirmation emails
- Update opportunity stages
- Create follow-up tasks

## Monitoring and Troubleshooting

### Error Logs
Monitor `PayPal_Error_Log__c` records for:
- API errors
- Authentication issues
- Validation failures
- Network timeouts

### Webhook Logs
Check `PayPal_Webhook_Log__c` for:
- Failed webhook processing
- Missing webhook events
- Signature validation issues

### Debug Logs
Enable debug logs for PayPal classes to troubleshoot issues:
```apex
System.debug('PayPal Request: ' + jsonRequest);
System.debug('PayPal Response: ' + response.getBody());
```

## Best Practices

### Security
- Never store PayPal credentials in code
- Use Named Credentials for API access
- Validate all webhook signatures
- Implement proper permission controls

### Performance
- Use caching for authentication tokens
- Implement retry logic for API calls
- Process webhooks asynchronously when possible
- Monitor API rate limits

### Testing
- Use PayPal sandbox for development
- Test all payment scenarios (success, failure, refund)
- Validate webhook processing
- Test error handling paths

## Support

For issues and questions:
1. Check the Error Logs in Salesforce
2. Verify PayPal Developer dashboard configuration
3. Review webhook processing logs
4. Contact your Salesforce administrator

## Contributing

To extend this integration:
1. Follow existing code patterns
2. Add proper error handling
3. Include unit tests
4. Update documentation
5. Test in sandbox environment first

---

**Note**: This integration is designed for Salesforce API version 61.0 and requires proper PayPal Developer account setup.
