// Countdown: makes every element marked class="countdown" and data-seconds="N" count down once a second, starting from the number the monitor wrote into the page.
(function () {
  // Remember when this page was opened, using the browser's steady clock (it ignores clock changes and any clock difference with Ollama).
  var start = performance.now();
  // Find every timer on the page.
  var items = document.querySelectorAll('.countdown[data-seconds]');
  // Nothing to do when there is no timer.
  if (items.length === 0) {
    // Stop here.
    return;
  }
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
  // Update every timer once.
  function tick() {
    // Seconds since the page opened.
    var elapsed = (performance.now() - start) / 1000;
    // Go through the timers.
    items.forEach(function (el) {
      // Seconds left: the number the monitor wrote minus the time passed, rounded up so 0 appears only at the end.
      var left = Math.ceil(Number(el.getAttribute('data-seconds')) - elapsed);
      // Show the time, or say the unload time has arrived.
      el.textContent = left > 0 ? words(left) : 'unloading now';
    });
  }
  // Show the first value at once, then every second.
  tick();
  // Repeat once a second.
  setInterval(tick, 1000);
})();
