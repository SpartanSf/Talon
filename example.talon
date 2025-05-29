#!/runTalon_nocache
use /talonlibs/io;

define void main() {
    let num: x = 0;
    loop(5, x);
};

define void loop(num: target, num: x) {
    x += 1;
    io.print(x);
    if (x == target) {
        return;
    };
    loop(target, x);
};
