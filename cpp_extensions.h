
// defer is an analog of Go's 'defer'.
#ifndef defer

template <typename T>
struct deferrer
{
	T fn;
	deferrer(T f) : fn(f) { };
	deferrer(const deferrer&) = delete;
	~deferrer() { fn(); }
};

#define DEFERRER_CONCAT_NX(a, b) a ## b
#define DEFERRER_CONCAT(a, b) DEFERRER_CONCAT_NX(a, b)
#define defer deferrer DEFERRER_CONCAT(__deferred, __COUNTER__) =

#endif
