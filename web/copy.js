// Copy buttons: each button with class "copybtn" copies the text of the element named in its data-target attribute (a command shown on the page) to the clipboard, so the person can paste it into a terminal. The script sends nothing anywhere and runs nothing; it only copies text that is already on the page.
(function () {
  // Find every copy button on the page.
  var buttons = document.querySelectorAll('button.copybtn[data-target]');
  // Nothing to do on a page without copy buttons.
  if (buttons.length === 0) {
    // Stop here.
    return;
  }
  // The invisible message that screen readers announce after a click.
  var live = document.getElementById('copystatus');
  // How long the button shows its answer ("Copied"), in milliseconds.
  var SHOW_MS = 2000;
  // Copy the old way: select the text in a hidden box and use the browser's copy command; this also works when the page is opened from another computer, where the newer clipboard function is not offered.
  function oldWay(text) {
    // A hidden text box that holds the text.
    var box = document.createElement('textarea');
    // Put the text in it.
    box.value = text;
    // The person cannot type into it.
    box.setAttribute('readonly', '');
    // The style sheet puts it outside the visible page (a script may not write inline styles under this page's security policy).
    box.className = 'copybox';
    // Add it to the page so that it can be selected.
    document.body.appendChild(box);
    // Select all of its text.
    box.select();
    // Whether the browser copied it.
    var ok = false;
    // Some browsers refuse the command with an error.
    try {
      // Ask the browser to copy the selected text.
      ok = document.execCommand('copy');
    } catch (e) {
      // A refusal counts as a failure.
      ok = false;
    }
    // Remove the box again.
    document.body.removeChild(box);
    // Tell the caller.
    return ok;
  }
  // Copy a text; the answer is a promise that says true when the text was copied.
  function copyText(text) {
    // The newer way works only on pages that the browser treats as secure (this computer's own address counts).
    if (navigator.clipboard && window.isSecureContext) {
      // Try it, and fall back to the old way when the browser refuses.
      return navigator.clipboard.writeText(text).then(function () {
        // Copied.
        return true;
      }, function () {
        // Refused: use the old way.
        return oldWay(text);
      });
    }
    // Otherwise use the old way straight away.
    return Promise.resolve(oldWay(text));
  }
  // Set up one button.
  function setUp(button) {
    // The word inside the button.
    var label = button.querySelector('.copylabel');
    // The word it normally shows.
    var normal = label ? label.textContent : '';
    // The timer that puts the normal word back.
    var timer = null;
    // The buttons are hidden in the page itself, so that without this script there is no button that does nothing.
    button.hidden = false;
    // What happens on a click.
    button.addEventListener('click', function () {
      // The element that holds the command.
      var source = document.getElementById(button.getAttribute('data-target'));
      // A missing element means a mistake in the page; do nothing.
      if (!source) {
        // Stop here.
        return;
      }
      // The command, without spaces at the ends.
      var text = source.textContent.trim();
      // Copy it.
      copyText(text).then(function (ok) {
        // Show the answer inside the button.
        if (label) {
          // Copied, or a short failure word.
          label.textContent = ok ? 'Copied' : 'Copy failed';
        }
        // Tell screen readers.
        if (live) {
          // The sentence.
          live.textContent = ok ? 'Command copied.' : 'Could not copy. Select the command and press Ctrl+C.';
        }
        // A second click starts the timer again.
        if (timer) {
          // Stop the old timer.
          clearTimeout(timer);
        }
        // Put the normal word back after a moment.
        timer = setTimeout(function () {
          // The normal word.
          if (label) {
            // Restore it.
            label.textContent = normal;
          }
        }, SHOW_MS);
      });
    });
  }
  // Set up every button.
  for (var i = 0; i < buttons.length; i++) {
    // One button.
    setUp(buttons[i]);
  }
})();
