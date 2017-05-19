var AWS = require('aws-sdk');
AWS.config.loadFromPath('./config.json');
var as = new AWS.AutoScaling();

asg_name = "kubernetes-minion-group-us-east-1b" ;
hook_name = "kube-lifecycle-hook"

var params = {
  AutoScalingGroupName: asg_name, 
  LifecycleHookName: hook_name, 
  LifecycleTransition: "autoscaling:EC2_INSTANCE_TERMINATING", 
  NotificationTargetARN: "arn:aws:sns:us-east-1:xxxxxxx:xxxx-kube-lifecyclehook01", 
  RoleARN: "arn:aws:iam::xxxxxxxx:role/kubernetes-lifecycle-hook-role"
 };
 as.putLifecycleHook(params, function(err, data) {
   if (err) console.log(err, err.stack); // an error occurred
   else     console.log(data);           // successful response
   /*
   data = {
   }
   */
 });
