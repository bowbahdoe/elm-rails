var _NoRedInk$elm_rails$Native_Rails = function(){

  var getCsrfToken = function() {
    // when we aren't in an actual dom
    if ((typeof window === "undefined") || (typeof process === 'object')){
      return { ctor : 'Nothing' };
    }

    var csrfTokenNode = document.head.querySelector('meta[name="csrf-token"]');
    var csrfToken =
        (csrfTokenNode === null || (typeof csrfTokenNode.content !== "string"))
            ? { ctor: 'Nothing' }
            : { ctor: 'Just', _0: csrfTokenNode.content };
    return csrfToken;
  };

  return {
    get csrfToken () {
      return getCsrfToken();
    }
  }
}();
