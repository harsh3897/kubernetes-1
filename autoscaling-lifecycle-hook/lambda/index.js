var AWS = require('aws-sdk');
var ec2 = new AWS.EC2();
var as = new AWS.AutoScaling();
var ssm = new AWS.SSM();

var async = require('async');
var sleep = require('sleep');

var documentName = 'kubernetesDrainNode' ; //name of the document to be executed on nodes

exports.handler = function(notification, context) {

    console.log("INFO: request Recieved.\nDetails:\n", JSON.stringify(notification));
    var message = JSON.parse(notification.Records[0].Sns.Message);
    console.log("DEBUG: SNS message contents. \nMessage:\n", message);

    var instanceId = message.EC2InstanceId;

    console.log(instanceId);
    var lifecycleParams = {
        "AutoScalingGroupName": message.AutoScalingGroupName,
        "LifecycleHookName": message.LifecycleHookName,
        "LifecycleActionToken": message.LifecycleActionToken,
        "LifecycleActionResult": "CONTINUE"
    };
    
    ec2.describeInstances({
        InstanceIds: [instanceId]
    }, function(err, data) {
        if (err) console.log(err, err.stack); // an error occurred
        else { 
	    console.log(data);
            nodename = data.Reservations[0].Instances[0].PrivateDnsName;
	    if(nodename == '') console.log("No Nodes to be drained");
	    else{
            console.log("Node that is going to be drained: ", nodename);
            executeCommand(nodename, lifecycleParams, context);
	    }
        }
    });
};

function executeCommand(nodename, lifecycleParams, context) {
    var ssmparams = {
        DocumentName: documentName,
        Comment: 'Draining Node', //any comment
        OutputS3BucketName: 'xxxxxxxx', //save the logs in this bucket
        OutputS3KeyPrefix: 'ssm-logs', //bucket prefix
        OutputS3Region: 'us-east-1', //region of bucket
        Targets: [{
            Key: 'tag:master', 
            Values: [
                'yes'
            ]
        }],  // execute the command on the server with this tag 
        Parameters: {
            'nodename': [
                nodename
            ]
        }
    };
    ssm.sendCommand(ssmparams, function(err, data) {
        if (err) console.log(err, err.stack);
        else {
            console.log(data);
            commandid = data.Command.CommandId;
            waitCommandSuccess(commandid, function waitCommandReadyCallback(err) {
                if (err) {
                    console.log("ERROR: Failure waiting for Command to be Success");
                } else
                    console.log("Command Status is Success");
                completeAsLifecycleAction(lifecycleParams, function lifecycleActionResponseHandler(err) {
                    if (err) {
                        context.fail();
                    } else {
                        //if we successfully notified AutoScaling of the instance status, tell lambda we succeeded
                        //even if the operation on the instance failed
                        context.succeed();
                    }
                });
            });
        }
    });
}

function waitCommandSuccess(commandid, waitCommandReadyCallback) {
    var commandStatus = undefined;
    async.until(
        function isSuccess(err) {
            return commandStatus === "Success";
        },
        function getCommandStatus(getCommandStatusCallback) {
            ssm.listCommands({
                CommandId: commandid
            }, function(err, data) {
                if (err) console.log(err, err.stack); 
                else {
                    console.log(data.Commands[0].Status);
                    commandStatus = data.Commands[0].Status;
                    sleep.sleep(2);
                    getCommandStatusCallback(err)
                }
            });
        },
        function waitCommandReadyCallbackClosure(err) {
            if (err) {
                console.log("ERROR: error waiting for Command to be success:\n", err);
            }
            waitCommandReadyCallback(err);
        }
    );
}

function completeAsLifecycleAction(lifecycleParams, callback) {
    //returns true on success or false on failure
    //notifies AutoScaling that it should either continue or abandon the instance
    as.completeLifecycleAction(lifecycleParams, function(err, data) {
        if (err) {
            console.log("ERROR: AS lifecycle completion failed.\nDetails:\n", err);
            console.log("DEBUG: CompleteLifecycleAction\nParams:\n", lifecycleParams);
            callback(err);
        } else {
            console.log("INFO: CompleteLifecycleAction Successful.\nReported:\n", data);
            callback(null);
        }
    });
}
