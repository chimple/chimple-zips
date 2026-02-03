#!/usr/bin/env node
/**
 * Copyright (c) 2022 Google LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 * the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
 */

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const zlib = require("node:zlib");

const debugPkg = require("debug");
const minimist = require("minimist");
const { GoogleAuth } = require("google-auth-library");

const debug = debugPkg("update-single-file");

const HOSTING_URL = "https://firebasehosting.googleapis.com/v1beta1";

async function main() {
  const argv = minimist(process.argv.slice(2));
  const PROJECT_ID = argv.project;
  if (!PROJECT_ID) {
    throw new Error("--project must be provided.");
  }

  const SITE_ID = argv.site || PROJECT_ID;
  const files = Array.from(argv._);

  if (!files.length) {
    throw new Error("No files provided.");
  }

  console.log("Deploying files:");
  for (const f of files) {
    console.log(`- ${f}`);
  }

  const filesByHash = {};
  for (const file of files) {
    const hash = await hashFile(file);
    filesByHash[hash] = file;
  }

  const auth = new GoogleAuth({
    scopes: "https://www.googleapis.com/auth/cloud-platform",
    projectId: PROJECT_ID,
  });

  const client = await auth.getClient();

  // Get current live version
  const res = await client.request({
    url: `${HOSTING_URL}/projects/${PROJECT_ID}/sites/${SITE_ID}/channels/live`,
  });

  const currentVersion = res.data.release.version.name;
  debug("Current version:", currentVersion);

  // Exclude replaced files
  const exclude = [];
  for (let f of Object.values(filesByHash)) {
    // strip public/
    const hostingPath = f.replace(/^public\//, "");
    exclude.push(`^/${hostingPath.replace(/\//g, "\\/")}$`);
  }

  // Clone version
  const cloneRes = await client.request({
    method: "POST",
    url: `${HOSTING_URL}/projects/${PROJECT_ID}/sites/${SITE_ID}/versions:clone`,
    body: JSON.stringify({
      sourceVersion: currentVersion,
      finalize: false,
      exclude: { regexes: exclude },
    }),
  });

  const operationName = cloneRes.data.name;
  let newVersion = "";

  while (true) {
    const opRes = await client.request({
      url: `${HOSTING_URL}/${operationName}`,
    });

    if (opRes.data.done) {
      newVersion = opRes.data.response.name;
      break;
    }
    await new Promise((r) => setTimeout(r, 1000));
  }

  debug("New version:", newVersion);

  // Populate files
  const data = {};
  for (const [hash, file] of Object.entries(filesByHash)) {
    // strip leading public/
    const hostingPath = file.replace(/^public\//, "");
    data[`/${hostingPath}`] = hash;
  }

  const populateRes = await client.request({
    method: "POST",
    url: `${HOSTING_URL}/projects/${PROJECT_ID}/${newVersion}:populateFiles`,
    body: JSON.stringify({ files: data }),
  });

  const uploadURL = populateRes.data.uploadUrl;
  const uploadRequiredHashes = populateRes.data.uploadRequiredHashes || [];

  for (const hash of uploadRequiredHashes) {
    const uploadRes = await client.request({
      method: "POST",
      url: `${uploadURL}/${hash}`,
      data: fs
        .createReadStream(filesByHash[hash])
        .pipe(zlib.createGzip({ level: 9 })),
    });

    if (uploadRes.status !== 200) {
      throw new Error(`Upload failed for ${filesByHash[hash]}`);
    }
  }

  // Finalize version
  await client.request({
    method: "PATCH",
    url: `${HOSTING_URL}/projects/${PROJECT_ID}/${newVersion}`,
    params: { updateMask: "status" },
    body: JSON.stringify({ status: "FINALIZED" }),
  });

  // Release
  await client.request({
    method: "POST",
    url: `${HOSTING_URL}/projects/${PROJECT_ID}/sites/${SITE_ID}/releases`,
    params: { versionName: newVersion },
    body: JSON.stringify({
      message: "Deployed via update-single-file (test)",
    }),
  });

  const siteRes = await client.request({
    url: `${HOSTING_URL}/projects/${PROJECT_ID}/sites/${SITE_ID}`,
  });

  console.log(`✅ Successfully deployed!`);
  console.log(`🌐 Site URL: ${siteRes.data.defaultUrl}`);
}

async function hashFile(file) {
  const hasher = crypto.createHash("sha256");
  const gzipper = zlib.createGzip({ level: 9 });
  const gzipStream = fs
    .createReadStream(path.resolve(process.cwd(), file))
    .pipe(gzipper);

  return new Promise((resolve, reject) => {
    hasher.once("readable", () => {
      const data = hasher.read();
      if (!data) {
        reject(new Error(`Could not hash ${file}`));
      } else {
        resolve(Buffer.isBuffer(data) ? data.toString("hex") : data);
      }
    });
    gzipStream.once("error", reject);
    gzipStream.pipe(hasher);
  });
}

main().catch((err) => {
  console.error("❌ Deployment failed:", err.message);
  process.exit(1);
});
