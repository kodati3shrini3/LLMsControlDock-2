// Countdown: makes every element marked class="countdown" and data-seconds="N" count down once a second, starting from the number the monitor wrote into the page. On the main page it also asks the monitor for fresh figures every few seconds, so each timer follows what Ollama really reports.
(function () {
  // Remember when this page was opened, using the browser's steady clock (it ignores clock changes and any clock difference with Ollama).
  var start = performance.now();
  // Find every timer on the page.
  var items = document.querySelectorAll('.countdown[data-seconds]');
  // The main page is the one that has the models table; the message pages do not.
  var onMain = document.querySelector('table.models') !== null;
  // Nothing to do when there is no timer and no table to keep fresh.
  if (items.length === 0 && !onMain) {
    // Stop here.
    return;
  }
  // How often the main page asks the monitor for fresh figures, in milliseconds.
  var POLL_MS = 10000;
  // How soon after the last request a timer that reached zero may ask again, in milliseconds.
  var QUICK_MS = 3000;
  // When the last request started, on the same steady clock.
  var lastPoll = performance.now();
  // True while a request is on its way, so two never overlap.
  var busy = false;
  // Turn a number of seconds into the same wording the monitor uses: "4 min 30 s", "1 h 5 min" or "20 s".
  function words(total) {
    // Whole hours.
    var h = Math.floor(total / 3600);
    // Whole minutes left over.
    var m = Math.floor((total % 3600) / 60);
    // Seconds left over.
    var s = total % 60;
    // With hours, show hours and minutes.
    if (h > 0) {
      // Hours and minutes.
      return h + ' h ' + m + ' min';
    }
    // With minutes, show minutes and seconds.
    if (m > 0) {
      // Minutes and seconds.
      return m + ' min ' + s + ' s';
    }
    // Otherwise only seconds.
    return s + ' s';
  }
  // Update every timer once; returns true when at least one timer has reached zero.
  function tick() {
    // Becomes true when a timer is at zero.
    var atZero = false;
    // Go through the timers.
    items.forEach(function (el) {
      // Seconds since this timer's number was written (the page opening, or the last fresh figures).
      var elapsed = (performance.now() - (el._t0 || start)) / 1000;
      // Seconds left: the number the monitor wrote minus the time passed, rounded up so 0 appears only at the end.
      var left = Math.ceil(Number(el.getAttribute('data-seconds')) - elapsed);
      // Show the time, or say the unload time has arrived.
      el.textContent = left > 0 ? words(left) : 'unloading now';
      // Remember that a timer reached zero.
      if (left <= 0) {
        // Flag it.
        atZero = true;
      }
    });
    // A timer that already says "unloading now" (the page was loaded after the time had passed) also counts as zero.
    if (document.querySelector('.timer[data-expired]')) {
      // Flag it.
      atZero = true;
    }
    // Tell the caller.
    return atZero;
  }
  // Describe the table in one text: each model, whether it is loaded, and whether its timer ticks; a change means the page itself must be redrawn.
  function signature(doc) {
    // One part per model row.
    var parts = [];
    // Go through the rows.
    doc.querySelectorAll('tr[data-model]').forEach(function (row) {
      // Name, loaded flag, and t when a ticking timer is present.
      parts.push(row.getAttribute('data-model') + '|' + row.getAttribute('data-loaded') + '|' + (row.querySelector('.countdown[data-seconds]') ? 't' : '-'));
    });
    // One text for the whole table.
    return parts.join('\n');
  }
  // Take the fresh figures from a freshly fetched copy of the page.
  function applyFresh(doc) {
    // The rows now on the page and the rows in the fresh copy; the signatures match, so they line up one to one.
    var now = document.querySelectorAll('tr[data-model]');
    // The fresh rows.
    var fresh = doc.querySelectorAll('tr[data-model]');
    // The moment the fresh figures arrived.
    var arrived = performance.now();
    // Go through the rows.
    for (var i = 0; i < now.length; i++) {
      // The timer element on the page and in the fresh copy (a row that is not loaded has none).
      var a = now[i].querySelector('.timer');
      // The fresh one.
      var b = fresh[i].querySelector('.timer');
      // Nothing to update for a row without a timer.
      if (!a || !b) {
        // Next row.
        continue;
      }
      // A ticking timer: take the new seconds and start counting from now.
      if (b.hasAttribute('data-seconds')) {
        // The new number.
        a.setAttribute('data-seconds', b.getAttribute('data-seconds'));
        // Restart this timer's clock.
        a._t0 = arrived;
      } else {
        // A fixed text such as "stays loaded": copy it.
        a.textContent = b.textContent;
      }
    }
    // Show the new values at once.
    tick();
  }
  // Ask the monitor for a fresh copy of the main page and compare it with what is shown.
  function poll() {
    // Skip while a request is running or the tab is hidden (no point asking when nobody looks).
    if (busy || document.hidden) {
      // Stop here.
      return;
    }
    // Mark the request as running and note the time.
    busy = true;
    // Note the time.
    lastPoll = performance.now();
    // Ask for the same page again, never from a cache, with the same cookies.
    fetch('/', { cache: 'no-store', credentials: 'same-origin' })
      .then(function (res) {
        // Anything but a normal answer is ignored until the next try.
        if (!res.ok) {
          // Throw to reach the catch below.
          throw new Error('bad status');
        }
        // Read the page text.
        return res.text();
      })
      .then(function (text) {
        // Turn the text into a page we can look into (nothing in it runs).
        var doc = new DOMParser().parseFromString(text, 'text/html');
        // A different set of models, loaded flags or timers (or no table at all) means the page must be redrawn: reload it.
        if (!doc.querySelector('table.models') || signature(doc) !== signature(document)) {
          // Reload the page from the monitor.
          location.reload();
          // Stop here.
          return;
        }
        // Nothing structural changed: take the fresh seconds.
        applyFresh(doc);
      })
      .catch(function () {
        // A failed request is not an error to show; the next try comes soon.
      })
      .then(function () {
        // Allow the next request.
        busy = false;
      });
  }
  // Show the first value at once, then every second.
  tick();
  // Repeat once a second; a timer at zero asks for fresh figures soon, so the row changes quickly after Ollama unloads the model.
  setInterval(function () {
    // Update the timers and see whether one is at zero.
    var atZero = tick();
    // On the main page, a timer at zero may ask again after a few seconds.
    if (onMain && atZero && performance.now() - lastPoll > QUICK_MS) {
      // Ask now.
      poll();
    }
  }, 1000);
  // The main page also asks regularly, and at once when its tab becomes visible again.
  if (onMain) {
    // Regular requests.
    setInterval(poll, POLL_MS);
    // Catch up after the tab was hidden.
    document.addEventListener('visibilitychange', function () {
      // Only when the tab has just become visible.
      if (!document.hidden) {
        // Ask now.
        poll();
      }
    });
  }
})();
