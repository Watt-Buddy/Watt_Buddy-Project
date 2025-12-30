const express = require('express');
const router = express.Router();

const {
  registerUser,
  loginUser
} = require('../controllers/authController');

router.get('/test', (req, res) => {
  res.json({ message: 'Auth routes working' });
});


router.post('/register', registerUser);
router.post('/login', loginUser);

module.exports = router;
