Package.describe({
  summary: "Simple facets with Mongo.",
  name: "hive:facets",
  version: "0.1.0"
});

Npm.depends({'json-stable-stringify': '1.0.0'});

Package.onUse(function(api, where) {
  api.versionsFrom("METEOR@1.0");
  api.use([
    'underscore',
    'coffeescript',
    'mongo',
    'check',
    'meteorhacks:aggregate@1.2.1'],
    ['client', 'server']);
  api.addFiles('facets.coffee', ['client', 'server']);
  api.export(['Facets'], ['client', 'server']);
});

/* TODO */
/*Package.onTest(function (api) {
});
*/

