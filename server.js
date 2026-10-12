const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

app.get('/', (req, res) => {
  res.json({
    status: 'success',
    message: 'Hello from Docker Multi-stage Build!',
    environment: 'production'
  });
});

app.listen(PORT, () => {
  console.log(`Server listening on port ${PORT}`);
});
