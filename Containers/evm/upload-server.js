const express = require('express');
const multer  = require('multer');
const path = require('path');
const fs = require('fs');

// Ensure /app/input exists
const uploadDir = '/app/input/';
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

const upload = multer({ dest: uploadDir });
const app = express();

app.post('/upload', upload.single('file'), (req, res) => {
  if (!req.file) {
    return res.status(400).json({ status: 'error', message: 'No file uploaded.' });
  }
  res.json({
    status: 'success',
    savedAs: req.file.filename,
    originalName: req.file.originalname,
    path: req.file.path
  });
});

const PORT = process.env.UPLOAD_PORT || 8080;
app.listen(PORT, () => {
  console.log(`Upload server running on port ${PORT}`);
});
