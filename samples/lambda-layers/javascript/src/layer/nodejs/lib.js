/**
 * Shared utility library for Lambda Layer.
 * This module is packaged as a Lambda Layer and extracted to /opt/nodejs/lib.js at runtime.
 */

module.exports = {
  echo: (o) => { console.log(o); return o }
};
