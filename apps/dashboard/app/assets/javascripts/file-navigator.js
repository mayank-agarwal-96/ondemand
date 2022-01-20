function launchFileNavigator(startingLocation)
{
    var url = '/pun/dev/dashboard/filesmin/fs/users/PZS0714/gbyrket';
    window.open(url, 'MyDialog',800,600,'menubar=0,toolbar=0');

    window.onmessage = function (e) {
        console.log('here');
    };

}