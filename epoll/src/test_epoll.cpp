#include <stdio.h>
#include <ryulib/SuperSocketServer.hpp>


int main(int argc, char *argv[]) {
	SuperSocketServer socket;

	socket.start(1234);
	getchar();
	socket.stop();

	while (socket.is_started()) ;

	return EXIT_SUCCESS;
}
