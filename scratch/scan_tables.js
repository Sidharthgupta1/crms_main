const fs = require('fs');
const path = require('path');

const sqlDir = '/Users/anmolrattan/Desktop/untitled folder 2/crms_main/SQL';
const rootDir = '/Users/anmolrattan/Desktop/untitled folder 2/crms_main';

const sqlFiles = [];

// Helper to scan directory for sql files
function scanDir(dir) {
  const files = fs.readdirSync(dir);
  for (const file of files) {
    const fullPath = path.join(dir, file);
    const stat = fs.statSync(fullPath);
    if (stat.isDirectory()) {
      if (file !== 'node_modules' && file !== '.git') {
        scanDir(fullPath);
      }
    } else if (file.endsWith('.sql')) {
      sqlFiles.push(fullPath);
    }
  }
}

scanDir(rootDir);

const tableRegex = /create\s+table\s+(\w+)/gi;
const uniqueTables = new Set();

for (const file of sqlFiles) {
  const content = fs.readFileSync(file, 'utf8');
  let match;
  while ((match = tableRegex.exec(content)) !== null) {
    uniqueTables.add(match[1].toLowerCase());
  }
}

console.log('--- UNIQUE TABLES FOUND ---');
const sortedTables = Array.from(uniqueTables).sort();
sortedTables.forEach((t, i) => {
  console.log(`${i + 1}. ${t}`);
});
console.log(`TOTAL UNIQUE TABLES: ${sortedTables.length}`);
