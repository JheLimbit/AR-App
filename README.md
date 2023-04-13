# ar_app

AR App

## Technical Details

Functionality right now is limited to flat forearm movement along the X plane, affecting the Z rotation of the model. If the user angles their arm forward toward the camera, the calculations for arm length will be thrown off.

Additionally, the current approach only allows for rotation along one axis right now. Adding other axises (?) of rotation changes the result drastically.

Right now all calculations and arm mapping is hardcoded to the right wrist, elbow and shoulder.

In the arm length calculation, 260 is the approximate length of the arm model
