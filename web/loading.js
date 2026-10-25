// Loading message: when the person confirms a load, hide the buttons, show the waiting box and count the seconds, because Ollama gives no percentage while it reads a model into memory.
(function () {
  // Find the confirm form of the load page (it is marked data-loading); other pages have none.
  var form = document.querySelector('form[data-loading]');
  // The box that holds the waiting message, and the buttons that it replaces.
  var box = document.getElementById('loading');
  // The row with the Yes and Cancel choices.
  var choices = document.getElementById('choices');
  // Nothing to do when this page has no such parts.
  if (!form || !box || !choices) {
    // Stop here.
    return;
  }
  // The place where the passed seconds are written.
  var elapsed = box.querySelector('.elapsed');
  // The repeating timer, kept so that it can be stopped.
  var timer = null;
  // Turn a number of seconds into wording: "45 s" or "2 min 5 s".
  function words(total) {
    // Whole minutes.
    var m = Math.floor(total / 60);
    // Seconds left over.
    var s = total % 60;
    // With minutes, show both.
    if (m > 0) {
      // Minutes and seconds.
      return m + ' min ' + s + ' s';
    }
    // Otherwise only seconds.
    return s + ' s';
  }
  // Put the page back as it was (used when the person comes back with the Back button and the browser kept the page in memory).
  function reset() {
    // Stop the timer.
    if (timer !== null) {
      // Cancel the repeat.
      clearInterval(timer);
      // Remember that it is stopped.
      timer = null;
    }
    // Hide the waiting message.
    box.hidden = true;
    // Show the buttons again.
    choices.hidden = false;
  }
  // When the form is sent, show the waiting message.
  form.addEventListener('submit', function () {
    // The steady clock, so a change of the computer clock does not matter.
    var start = performance.now();
    // Do the changes just after the browser has started sending the form, so the form data is certainly complete.
    setTimeout(function () {
      // Hide the buttons: this also stops a second click and a second load.
      choices.hidden = true;
      // Show the waiting message.
      box.hidden = false;
      // Write the first value at once.
      elapsed.textContent = words(0);
      // Then update every second.
      timer = setInterval(function () {
        // Whole seconds since the form was sent.
        elapsed.textContent = words(Math.floor((performance.now() - start) / 1000));
      }, 1000);
    }, 0);
  });
  // The page can come back from the browser's memory after Back; then the waiting state must not stay.
  window.addEventListener('pageshow', function (e) {
    // Only a page restored from memory needs the reset.
    if (e.persisted) {
      // Reset it.
      reset();
    }
  });
})();
