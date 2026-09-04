// ============================================================
// WhatsApp "Smart Paste" parser (Sections 12/13) — extracts a
// line-based "Label: Value" message (the format staff realistically
// relay a customer's details in) into structured fields. Deliberately
// conservative: a field it isn't confident about is left BLANK and
// flagged in `needsConfirmation` rather than guessed — this is a data
// -entry aid, never an auto-booking path. The caller (whatsapp-
// booking.html) always shows every field for a human to review/edit
// before create_booking() is ever called.
// ============================================================

function extractField(text, labels) {
  for (const label of labels) {
    const re = new RegExp(`${label}\\s*[:\\-]\\s*(.+)`, 'i');
    const m = text.match(re);
    if (m && m[1].trim()) return m[1].split('\n')[0].trim();
  }
  return '';
}

export function parseWhatsAppBooking(raw) {
  const text = String(raw || '').replace(/\r\n/g, '\n');

  const name = extractField(text, ['patient name', 'customer name', 'name']);

  const phoneRaw = extractField(text, ['phone number', 'mobile number', 'customer phone no\\.?', 'phone', 'mobile', 'contact']);
  const phoneDigits = (phoneRaw.match(/\d{10,}/) || [phoneRaw.replace(/\D/g, '')])[0] || '';
  const phone = phoneDigits.slice(-10);

  const age = extractField(text, ['age']).replace(/\D/g, '');

  const genderRaw = extractField(text, ['gender', 'sex']);
  const gender = /^f/i.test(genderRaw) ? 'female' : /^m/i.test(genderRaw) ? 'male' : genderRaw ? 'other' : '';

  const itemName = extractField(text, ['test/package', 'package', 'test details', 'test']);

  const collectionRaw = extractField(text, ['collection type', 'collection']);
  const collectionType = /home/i.test(collectionRaw) ? 'home' : /walk|lab|clinic/i.test(collectionRaw) ? 'lab_visit' : '';

  const address = extractField(text, ['customer address', 'address']);
  const pincode = (address.match(/\b(\d{6})\b/) || [])[1] || '';

  // Date/time are intentionally NOT auto-converted into a real date —
  // free text like "10 Sept" or "tomorrow 5pm" is exactly the kind of
  // ambiguous input Section 13 says not to guess on. Shown as a raw
  // hint; staff pick the real date/slot from the actual pickers.
  const dateHint = extractField(text, ['date']);
  const timeHint = extractField(text, ['time', 'slot', 'sample collection slot timings?']);

  const fields = { name, phone, age, gender, itemName, collectionType, address, pincode, dateHint, timeHint };

  const needsConfirmation = [];
  if (!name) needsConfirmation.push('Patient Name');
  if (!phone || phone.length !== 10) needsConfirmation.push('Phone');
  if (!itemName) needsConfirmation.push('Test/Package');
  if (!collectionType) needsConfirmation.push('Collection Type');
  if (!dateHint) needsConfirmation.push('Date');
  if (!timeHint) needsConfirmation.push('Time');

  return { fields, needsConfirmation };
}
