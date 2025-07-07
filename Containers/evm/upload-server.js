const express = require('express');
const multer  = require('multer');
const path = require('path');

const upload = multer({ dest: '/app/input/' });
const app = express();

app.post('/upload', upload.single('file'), (req, res) => {
  if (!req.file) {
    return res.status(400).send('No file uploaded.');
  }
  res.json({ status: 'success', filename: req.file.filename, originalname: req.file.originalname });
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`Upload server running on port ${PORT}`);
});
