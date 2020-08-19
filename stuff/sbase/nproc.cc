#include <iostream>
#include <thread>

int main() {
	std::cout << std::thread::hardware_concurrency() << std::endl;
	return 0;
}
