// Sort by choice on the Find LLM page: when the person changes it while models are listed, the page sends the form to the re-sort address, so the models already shown are put in the new order at once (nothing is read from the internet).
(function () {
  // The choice carries the re-sort address only when models are listed.
  var pick = document.querySelector('select[data-resort]');
  // Nothing to do without it.
  if (!pick || !pick.form) {
    // Stop here.
    return;
  }
  // When the person picks another order.
  pick.addEventListener('change', function () {
    // Send the form to the re-sort address instead of the search address.
    pick.form.action = pick.getAttribute('data-resort');
    // Send it now (this skips the form checks, which do not matter for a sort).
    pick.form.submit();
  });
})();
