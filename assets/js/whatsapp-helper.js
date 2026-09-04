// ============================================================
// WhatsApp helper — shared by the customer confirmation page and the
// admin Add Booking / WhatsApp Booking pages. This is a wa.me
// click-to-chat link generator ONLY — there is no WhatsApp Business
// API integration anywhere in this project (matches
// BACKEND_DEPENDENCIES.md §8's documented state of the original app).
// Clicking the resulting link opens WhatsApp (app or Web) with the
// message pre-filled; nothing is ever sent automatically, and no code
// anywhere should claim otherwise.
// ============================================================

/** Indian-mobile-first normalizer: keeps only digits, takes the last
 * 10, and prefixes the country code wa.me requires. Never throws —
 * a malformed number just produces a link WhatsApp itself will reject
 * gracefully rather than crashing the page. */
export function normalizePhoneForWhatsApp(phone) {
  const digits = String(phone || '').replace(/\D/g, '');
  const last10 = digits.slice(-10);
  return last10.length === 10 ? '91' + last10 : digits;
}

export function buildWhatsAppLink(phone, message) {
  return `https://wa.me/${normalizePhoneForWhatsApp(phone)}?text=${encodeURIComponent(message)}`;
}

/**
 * Builds the customer-facing booking confirmation message (Section 14).
 * Every field is optional except bookingCode/patientName — a missing
 * field is simply omitted rather than shown as "undefined".
 */
export function buildBookingConfirmationMessage({
  bookingCode, patientName, itemName, collectionType, dateStr, slotLabel,
  amount, addressLine, city, pincode, supportPhone,
}) {
  const lines = [
    '🏥 *My Prime Diagnostic*',
    '✅ *Booking Confirmation*',
    '',
    `Booking ID: ${bookingCode}`,
  ];
  if (patientName) lines.push(`Patient: ${patientName}`);
  if (itemName) lines.push(`Test/Package: ${itemName}`);
  if (collectionType) lines.push(`Collection: ${collectionType === 'home' ? 'Home Collection' : 'Walk-in at Lab'}`);
  if (dateStr) lines.push(`Date & Time: ${dateStr}${slotLabel ? ', ' + slotLabel : ''}`);
  if (amount != null) lines.push(`Amount: ₹${Number(amount).toLocaleString('en-IN')}`);
  if (collectionType === 'home' && addressLine) {
    lines.push(`Address: ${addressLine}${city ? ', ' + city : ''}${pincode ? ' - ' + pincode : ''}`);
  }
  lines.push('', `Track your booking anytime: ${location.origin}/pages/track-booking.html?code=${encodeURIComponent(bookingCode)}`);
  lines.push(`Support: ${supportPhone || '+91 74284 56590'}`);
  return lines.join('\n');
}
