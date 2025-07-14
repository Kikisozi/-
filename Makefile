# 定义最终生成的文件名
DYLIB_NAME = ColorHook.dylib

# 定义默认的编译任务
all:
	@echo "--- [最终审查版] 开始编译 ---"
	# 链接 Foundation, OpenGLES, 和 UIKit 框架
	clang -w -dynamiclib -arch arm64 -isysroot `xcrun --sdk iphoneos --show-sdk-path` \
	-framework Foundation -framework OpenGLES -framework UIKit \
	ColorHook.m -o $(DYLIB_NAME)
	@echo "--- [最终审查版] 编译完成 ---"
