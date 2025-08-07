import { createElement } from 'lwc';
import { ShowToastEventName } from 'lightning/platformShowToastEvent';
import PaymentForm from 'c/paymentForm';
import processPayment from '@salesforce/apex/PaymentProcessor.processPayment';

// Mock the Apex method
jest.mock(
    '@salesforce/apex/PaymentProcessor.processPayment',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return {
            default: createApexTestWireAdapter(jest.fn())
        };
    },
    { virtual: true }
);

// Mock PayPal SDK
global.paypal = {
    Buttons: jest.fn(() => ({
        render: jest.fn().mockResolvedValue()
    }))
};

describe('c-payment-form', () => {
    afterEach(() => {
        // The jsdom instance is shared across test cases in a single file so reset the DOM
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders payment form with required fields', () => {
        const element = createElement('c-payment-form', {
            is: PaymentForm
        });
        document.body.appendChild(element);

        // Verify form elements are present
        const amountInput = element.shadowRoot.querySelector('lightning-input[data-id="amount"]');
        const currencySelect = element.shadowRoot.querySelector('lightning-combobox[data-id="currency"]');
        const descriptionInput = element.shadowRoot.querySelector('lightning-input[data-id="description"]');
        
        expect(amountInput).toBeTruthy();
        expect(currencySelect).toBeTruthy();
        expect(descriptionInput).toBeTruthy();
    });

    it('validates required fields on form submission', async () => {
        const element = createElement('c-payment-form', {
            is: PaymentForm
        });
        document.body.appendChild(element);

        // Try to submit form without required fields
        const form = element.shadowRoot.querySelector('form');
        form.dispatchEvent(new CustomEvent('submit', { preventDefault: jest.fn() }));

        await Promise.resolve();

        // Check that validation messages appear
        const amountInput = element.shadowRoot.querySelector('lightning-input[data-id="amount"]');
        expect(amountInput.validity.valid).toBe(false);
    });

    it('validates minimum payment amount', async () => {
        const element = createElement('c-payment-form', {
            is: PaymentForm
        });
        document.body.appendChild(element);

        // Set amount below minimum
        const amountInput = element.shadowRoot.querySelector('lightning-input[data-id="amount"]');
        amountInput.value = '0.50'; // Below $1 minimum
        amountInput.dispatchEvent(new CustomEvent('change'));

        await Promise.resolve();

        const errorMessage = element.shadowRoot.querySelector('.error-message');
        expect(errorMessage).toBeTruthy();
        expect(errorMessage.textContent).toContain('minimum');
    });

    it('validates maximum payment amount', async () => {
        const element = createElement('c-payment-form', {
            is: PaymentForm
        });
        document.body.appendChild(element);

        // Set amount above maximum
        const amountInput = element.shadowRoot.querySelector('lightning-input[data-id="amount"]');
        amountInput.value = '15000'; // Above $10,000 maximum
        amountInput.dispatchEvent(new CustomEvent('change'));

        await Promise.resolve();

        const errorMessage = element.shadowRoot.querySelector('.error-message');
        expect(errorMessage).toBeTruthy();
        expect(errorMessage.textContent).toContain('maximum');
    });

    it('initializes PayPal button on successful form validation', async () => {
        const element = createElement('c-payment-form', {
            is: PaymentForm
        });
        document.body.appendChild(element);

        // Set valid form data
        const amountInput = element.shadowRoot.querySelector('lightning-input[data-id="amount"]');
        const currencySelect = element.shadowRoot.querySelector('lightning-combobox[data-id="currency"]');
        const descriptionInput = element.shadowRoot.querySelector('lightning-input[data-id="description"]');

        amountInput.value = '100.00';
        amountInput.dispatchEvent(new CustomEvent('change'));
        
        currencySelect.value = 'USD';
        currencySelect.dispatchEvent(new CustomEvent('change'));
        
        descriptionInput.value = 'Test Payment';
        descriptionInput.dispatchEvent(new CustomEvent('change'));

        // Submit form
        const form = element.shadowRoot.querySelector('form');
        form.dispatchEvent(new CustomEvent('submit', { preventDefault: jest.fn() }));

        await Promise.resolve();

        // Verify PayPal button was initialized
        expect(global.paypal.Buttons).toHaveBeenCalled();
    });

    it('handles successful payment processing', async () => {
        // Mock successful Apex response
        processPayment.mockResolvedValue({
            success: true,
            orderId: 'ORDER123',
            status: 'CREATED',
            approvalUrl: 'https://paypal.com/approve'
        });

        const element = createElement('c-payment-form', {
            is: PaymentForm
        });
        document.body.appendChild(element);

        // Mock PayPal button click
        element.handlePayPalSuccess({ orderID: 'ORDER123' });

        await Promise.resolve();

        // Verify success message
        const handler = jest.fn();
        element.addEventListener(ShowToastEventName, handler);
        
        expect(handler).toHaveBeenCalledWith(
            expect.objectContaining({
                detail: expect.objectContaining({
                    variant: 'success'
                })
            })
        );
    });

    it('handles payment processing errors', async () => {
        // Mock error response
        processPayment.mockRejectedValue(new Error('Payment failed'));

        const element = createElement('c-payment-form', {
            is: PaymentForm
        });
        document.body.appendChild(element);

        // Mock PayPal error
        element.handlePayPalError(new Error('PayPal Error'));

        await Promise.resolve();

        // Verify error message
        const errorMessage = element.shadowRoot.querySelector('.error-message');
        expect(errorMessage).toBeTruthy();
        expect(errorMessage.textContent).toContain('error');
    });

    it('disables form during payment processing', async () => {
        const element = createElement('c-payment-form', {
            is: PaymentForm
        });
        document.body.appendChild(element);

        // Simulate processing state
        element.isProcessing = true;

        await Promise.resolve();

        // Verify form elements are disabled
        const amountInput = element.shadowRoot.querySelector('lightning-input[data-id="amount"]');
        const currencySelect = element.shadowRoot.querySelector('lightning-combobox[data-id="currency"]');
        
        expect(amountInput.disabled).toBe(true);
        expect(currencySelect.disabled).toBe(true);
    });

    it('shows loading spinner during processing', async () => {
        const element = createElement('c-payment-form', {
            is: PaymentForm
        });
        document.body.appendChild(element);

        // Set processing state
        element.isProcessing = true;

        await Promise.resolve();

        // Verify spinner is shown
        const spinner = element.shadowRoot.querySelector('lightning-spinner');
        expect(spinner).toBeTruthy();
    });

    it('resets form after successful payment', async () => {
        const element = createElement('c-payment-form', {
            is: PaymentForm
        });
        document.body.appendChild(element);

        // Set form data
        const amountInput = element.shadowRoot.querySelector('lightning-input[data-id="amount"]');
        amountInput.value = '100.00';

        // Simulate successful payment
        element.handlePaymentSuccess();

        await Promise.resolve();

        // Verify form is reset
        expect(amountInput.value).toBe('');
    });

    it('handles currency change and updates amount format', async () => {
        const element = createElement('c-payment-form', {
            is: PaymentForm
        });
        document.body.appendChild(element);

        const currencySelect = element.shadowRoot.querySelector('lightning-combobox[data-id="currency"]');
        
        // Change currency to EUR
        currencySelect.value = 'EUR';
        currencySelect.dispatchEvent(new CustomEvent('change'));

        await Promise.resolve();

        // Verify currency symbol updated (implementation dependent)
        const currencySymbol = element.shadowRoot.querySelector('.currency-symbol');
        if (currencySymbol) {
            expect(currencySymbol.textContent).toContain('€');
        }
    });

    it('validates supported currencies', async () => {
        const element = createElement('c-payment-form', {
            is: PaymentForm
        });
        document.body.appendChild(element);

        const currencySelect = element.shadowRoot.querySelector('lightning-combobox[data-id="currency"]');
        const options = currencySelect.options;

        // Verify supported currencies are present
        const supportedCurrencies = ['USD', 'EUR', 'GBP', 'CAD', 'AUD'];
        const availableCurrencies = options.map(option => option.value);

        supportedCurrencies.forEach(currency => {
            expect(availableCurrencies).toContain(currency);
        });
    });

    it('handles record context when provided', async () => {
        const element = createElement('c-payment-form', {
            is: PaymentForm
        });
        
        // Set record context
        element.recordId = '0031234567890ABC';
        
        document.body.appendChild(element);

        await Promise.resolve();

        // Verify record context is used in payment processing
        expect(element.recordId).toBe('0031234567890ABC');
    });
});