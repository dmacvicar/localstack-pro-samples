/**
 * Lambda function that uses the shared layer.
 * The layer is extracted to /opt/nodejs/ at runtime.
 */

const { echo } = require('/opt/nodejs/lib');

module.exports.hello = async function(event, context) {
  const message = 'Hello from Lambda Layer!';
  echo(message);

  return {
    statusCode: 200,
    body: JSON.stringify({
      message: message,
      layerWorking: true
    })
  };
}
