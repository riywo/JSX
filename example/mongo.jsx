import "js.jsx";

native final __fake__ class ReplicaSet {
    function status() : Message;

}

class Message {
    var errmsg : string;
}

class _Main {
    static function main (args : string[]) : void {
        var rs = js.global["rs"] as __noconvert__ ReplicaSet;
        log rs.status().errmsg;
    }
}
