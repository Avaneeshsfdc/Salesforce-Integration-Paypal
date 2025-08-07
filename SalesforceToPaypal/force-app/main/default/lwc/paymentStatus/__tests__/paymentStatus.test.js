import { createElement } from 'lwc';
import PaymentStatus from 'c/paymentStatus';
import capturePayment from '@salesforce/apex/PaymentProcessor.capturePayment';
import refundPayment from '@salesforce/apex/PaymentProcessor.refundPayment';

// Mock the Apex methods
jest.mock(
    '@salesforce/apex/PaymentProcessor.capturePayment',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return {
            default: createApexTestWireAdapter(jest.fn())
        };
    },
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/PaymentProcessor.refundPayment',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return {
            default: createApexTestWireAdapter(jest.fn())
        };
    },
    { virtual: true }
);

describe('c-payment-status', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('displays pending status correctly', () => {
        const element = createElement('c-payment-status', {
            is: PaymentStatus
        });
        
        element.paymentStatus = 'Pending';
        document.body.appendChild(element);

        const statusBadge = element.shadowRoot.querySelector('.status-badge');
        expect(statusBadge).toBeTruthy();
        expect(statusBadge.textContent).toContain('Pending');
        expect(statusBadge).toHaveClass('status-pending');
    });

    it('displays completed status with success styling', () => {
        const element = createElement('c-payment-status', {
            is: PaymentStatus
        });
        
        element.paymentStatus = 'Completed';
        document.body.appendChild(element);

        const statusBadge = element.shadowRoot.querySelector('.status-badge');
        expect(statusBadge.textContent).toContain('Completed');
        expect(statusBadge).toHaveClass('status-completed');
    });

    it('displays failed status with error styling', () => {
        const element = createElement('c-payment-status', {
            is: PaymentStatus
        });
        
        element.paymentStatus = 'Failed';
        document.body.appendChild(element);

        const statusBadge = element.shadowRoot.querySelector('.status-badge');
        expect(statusBadge.textContent).toContain('Failed');
        expect(statusBadge).toHaveClass('status-failed');
    });

    it('shows capture button for approved payments', () => {
        const element = createElement('c-payment-status', {
            is: PaymentStatus
        });
        
        element.paymentStatus = 'Approved';
        element.orderId = 'ORDER123';
        document.body.appendChild(element);

        const captureButton = element.shadowRoot.querySelector('[data-id="capture-btn"]');
        expect(captureButton).toBeTruthy();
        expect(captureButton.disabled).toBe(false);
    });

    it('shows refund button for completed payments', () => {
        const element = createElement('c-payment-status', {
            is: PaymentStatus
        });
        
        element.paymentStatus = 'Completed';
        element.orderId = 'ORDER123';
        element.amount = 100.00;
        document.body.appendChild(element);

        const refundButton = element.shadowRoot.querySelector('[data-id="refund-btn"]');
        expect(refundButton).toBeTruthy();
        expect(refundButton.disabled).toBe(false);
    });

    it('hides action buttons for pending payments', () => {
        const element = createElement('c-payment-status', {
            is: PaymentStatus
        });
        
        element.paymentStatus = 'Pending';
        document.body.appendChild(element);

        const captureButton = element.shadowRoot.querySelector('[data-id="capture-btn"]');
        const refundButton = element.shadowRoot.querySelector('[data-id="refund-btn"]');
        
        expect(captureButton).toBeFalsy();
        expect(refundButton).toBeFalsy();
    });

    it('handles capture payment action', async () => {
        capturePayment.mockResolvedValue({
            success: true,
            status: 'Completed'
        });

        const element = createElement('c-payment-status', {
            is: PaymentStatus
        });
        
        element.paymentStatus = 'Approved';
        element.orderId = 'ORDER123';
        document.body.appendChild(element);

        const captureButton = element.shadowRoot.querySelector('[data-id="capture-btn"]');
        captureButton.click();

        await Promise.resolve();

        expect(capturePayment).toHaveBeenCalledWith({ orderId: 'ORDER123' });
    });

    it('handles refund payment action', async () => {
        refundPayment.mockResolvedValue({
            success: true,
            status: 'Refunded'
        });

        const element = createElement('c-payment-status', {
            is: PaymentStatus
        });
        
        element.paymentStatus = 'Completed';
        element.orderId = 'ORDER123';
        element.amount = 100.00;
        element.currency = 'USD';
        document.body.appendChild(element);

        // Open refund modal
        const refundButton = element.shadowRoot.querySelector('[data-id="refund-btn"]');
        refundButton.click();

        await Promise.resolve();

        // Set refund amount and confirm
        const refundAmountInput = element.shadowRoot.querySelector('[data-id="refund-amount"]');
        refundAmountInput.value = '50.00';
        refundAmountInput.dispatchEvent(new CustomEvent('change'));

        const confirmRefundButton = element.shadowRoot.querySelector('[data-id="confirm-refund-btn"]');
        confirmRefundButton.click();

        await Promise.resolve();

        expect(refundPayment).toHaveBeenCalledWith({
            orderId: 'ORDER123',
            amount: 50.00,
            currency: 'USD'
        });
    });

    it('validates refund amount does not exceed original amount', async () => {
        const element = createElement('c-payment-status', {
            is: PaymentStatus
        });
        
        element.paymentStatus = 'Completed';
        element.amount = 100.00;
        document.body.appendChild(element);

        // Open refund modal
        const refundButton = element.shadowRoot.querySelector('[data-id="refund-btn"]');
        refundButton.click();

        await Promise.resolve();

        // Set refund amount higher than original
        const refundAmountInput = element.shadowRoot.querySelector('[data-id="refund-amount"]');
        refundAmountInput.value = '150.00';
        refundAmountInput.dispatchEvent(new CustomEvent('change'));

        await Promise.resolve();

        const errorMessage = element.shadowRoot.querySelector('.refund-error');
        expect(errorMessage).toBeTruthy();
        expect(errorMessage.textContent).toContain('cannot exceed');
    });

    it('disables buttons during processing', async () => {
        const element = createElement('c-payment-status', {
            is: PaymentStatus
        });
        
        element.paymentStatus = 'Approved';
        element.orderId = 'ORDER123';
        element.isProcessing = true;
        document.body.appendChild(element);

        await Promise.resolve();

        const captureButton = element.shadowRoot.querySelector('[data-id="capture-btn"]');
        expect(captureButton.disabled).toBe(true);
    });

    it('shows loading spinner during processing', async () => {
        const element = createElement('c-payment-status', {
            is: PaymentStatus
        });
        
        element.isProcessing = true;
        document.body.appendChild(element);

        const spinner = element.shadowRoot.querySelector('lightning-spinner');
        expect(spinner).toBeTruthy();
    });

    it('displays payment details when provided', () => {
        const element = createElement('c-payment-status', {
            is: PaymentStatus
        });
        
        element.paymentDetails = {
            amount: 100.00,
            currency: 'USD',
            description: 'Test Payment',
            orderId: 'ORDER123',
            createdDate: '2024-01-01T00:00:00Z'
        };
        document.body.appendChild(element);

        const amountDisplay = element.shadowRoot.querySelector('.payment-amount');
        const descriptionDisplay = element.shadowRoot.querySelector('.payment-description');
        
        expect(amountDisplay.textContent).toContain('$100.00');
        expect(descriptionDisplay.textContent).toContain('Test Payment');
    });

    it('handles capture payment error gracefully', async () => {
        capturePayment.mockRejectedValue(new Error('Capture failed'));

        const element = createElement('c-payment-status', {
            is: PaymentStatus
        });
        
        element.paymentStatus = 'Approved';
        element.orderId = 'ORDER123';
        document.body.appendChild(element);

        const captureButton = element.shadowRoot.querySelector('[data-id="capture-btn"]');
        captureButton.click();

        await Promise.resolve();

        const errorMessage = element.shadowRoot.querySelector('.error-message');
        expect(errorMessage).toBeTruthy();
        expect(errorMessage.textContent).toContain('error');
    });

    it('handles refund payment error gracefully', async () => {
        refundPayment.mockRejectedValue(new Error('Refund failed'));

        const element = createElement('c-payment-status', {
            is: PaymentStatus
        });
        
        element.paymentStatus = 'Completed';
        element.orderId = 'ORDER123';
        element.amount = 100.00;
        element.currency = 'USD';
        document.body.appendChild(element);

        // Open refund modal and confirm
        const refundButton = element.shadowRoot.querySelector('[data-id="refund-btn"]');
        refundButton.click();

        await Promise.resolve();

        const refundAmountInput = element.shadowRoot.querySelector('[data-id="refund-amount"]');
        refundAmountInput.value = '50.00';

        const confirmRefundButton = element.shadowRoot.querySelector('[data-id="confirm-refund-btn"]');
        confirmRefundButton.click();

        await Promise.resolve();

        const errorMessage = element.shadowRoot.querySelector('.error-message');
        expect(errorMessage).toBeTruthy();
        expect(errorMessage.textContent).toContain('error');
    });

    it('closes refund modal when cancelled', async () => {
        const element = createElement('c-payment-status', {
            is: PaymentStatus
        });
        
        element.paymentStatus = 'Completed';
        document.body.appendChild(element);

        // Open refund modal
        const refundButton = element.shadowRoot.querySelector('[data-id="refund-btn"]');
        refundButton.click();

        await Promise.resolve();

        // Cancel refund
        const cancelButton = element.shadowRoot.querySelector('[data-id="cancel-refund-btn"]');
        cancelButton.click();

        await Promise.resolve();

        const refundModal = element.shadowRoot.querySelector('.refund-modal');
        expect(refundModal).toBeFalsy();
    });

    it('updates status after successful capture', async () => {
        capturePayment.mockResolvedValue({
            success: true,
            status: 'Completed'
        });

        const element = createElement('c-payment-status', {
            is: PaymentStatus
        });
        
        element.paymentStatus = 'Approved';
        element.orderId = 'ORDER123';
        document.body.appendChild(element);

        const captureButton = element.shadowRoot.querySelector('[data-id="capture-btn"]');
        captureButton.click();

        await Promise.resolve();

        expect(element.paymentStatus).toBe('Completed');
    });

    it('updates status after successful refund', async () => {
        refundPayment.mockResolvedValue({
            success: true,
            status: 'Refunded'
        });

        const element = createElement('c-payment-status', {
            is: PaymentStatus
        });
        
        element.paymentStatus = 'Completed';
        element.orderId = 'ORDER123';
        element.amount = 100.00;
        element.currency = 'USD';
        document.body.appendChild(element);

        // Process refund
        const refundButton = element.shadowRoot.querySelector('[data-id="refund-btn"]');
        refundButton.click();

        await Promise.resolve();

        const refundAmountInput = element.shadowRoot.querySelector('[data-id="refund-amount"]');
        refundAmountInput.value = '100.00';

        const confirmRefundButton = element.shadowRoot.querySelector('[data-id="confirm-refund-btn"]');
        confirmRefundButton.click();

        await Promise.resolve();

        expect(element.paymentStatus).toBe('Refunded');
    });
});