import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(here, "../..");
const beamUiRoot = process.env.BEAMNG_UI_ROOT ||
  "D:/SteamLibrary/steamapps/common/BeamNG.drive/ui";

const contentTypes = {
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".mp3": "audio/mpeg",
  ".png": "image/png",
  ".ttf": "font/ttf",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
};

const resolveRequest = (urlPath) => {
  if (urlPath === "/" || urlPath === "/tests/ui/harness.html") {
    return path.join(here, "harness.html");
  }
  if (urlPath.startsWith("/tests/ui/")) {
    return path.join(here, urlPath.slice("/tests/ui/".length));
  }
  if (urlPath.startsWith("/ui/modules/apps/TaxiDriverHUD/")) {
    return path.join(repositoryRoot, urlPath.slice(1));
  }
  if (urlPath.startsWith("/ui/common/")) {
    return path.join(beamUiRoot, urlPath.slice("/ui/".length));
  }
  if (urlPath.startsWith("/beamng/")) {
    return path.join(beamUiRoot, "lib/ext", urlPath.slice("/beamng/".length));
  }
  return null;
};

export const startHarnessServer = (port = 41735) => new Promise((resolve, reject) => {
  const server = http.createServer((request, response) => {
    const url = new URL(request.url, `http://${request.headers.host || "127.0.0.1"}`);
    const filename = resolveRequest(decodeURIComponent(url.pathname));
    if (!filename || !fs.existsSync(filename) || !fs.statSync(filename).isFile()) {
      response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
      response.end("Not found");
      return;
    }
    response.writeHead(200, {
      "cache-control": "no-store",
      "content-type": contentTypes[path.extname(filename).toLowerCase()] || "application/octet-stream",
    });
    fs.createReadStream(filename).pipe(response);
  });
  server.once("error", reject);
  server.listen(port, "127.0.0.1", () => resolve({ server, port }));
});

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const port = Number(process.env.TAXIDRIVER_TEST_PORT || 41735);
  const running = await startHarnessServer(port);
  console.log(`TaxiDriver UI harness: http://127.0.0.1:${running.port}/`);
}
