# 通道

<!-- toc -->

通道（Channel） 提供与 IO 服务的直接连接，使用 Channel 我们可以在字节缓冲区和通道另一侧的实体（通常是一个文件或者套接字）之间有效的传输数据。Channel 主要分为两类：File Channel（文件通道）和 Socket Channel（套接字通道）

## FileChannel
FileChannel 主要用来处理文件，FileChannel 总是运行在阻塞模式下，无法将其设置为非阻塞模式。FileChannel 是线程安全的，多个进程可以在同一个实例上并发调用相关方法，不过对于影响 Channel 位置（position）或者文件大小的操作都进行同步处理。

### 打开
FileChannel 不能直接创建，而是要创建一个文件对象（RandomAccessFile、FileInputStream、FileOutputStream），然后再调用 getChannel 方法获得。
```java
RandomAccessFile randomAccessFile = new RandomAccessFile(filePath, "rw");
FileChannel fileChannel = randomAccessFile.getChannel();
```
RandomAccessFile 打开文件的模式有下面四种
* "r" - 只读
* "rw" - 可读写文件，如果文件不存在，则创建文件
* "rws" - 可读写文件，并且文件数据以及元数据的每个更新都会写入磁盘
* "rwd" - 可读写文件，并且文件数据的每个更新操作都会写入到磁盘

RandomAccessFile 对象采用 lazy-load 的方式创建 FileChannel，创建完之后会将 FileChannel 缓存起来，并进行了同步处理，下面是相关代码：
```java
public final FileChannel getChannel() {
    synchronized(this) {
        if (channel == null) {
            channel = FileChannelImpl.open(fd, path, true, rw, this);
        }
        return channel;
    }
}
```
### 从 FileChannel中读取数据
通过 read 方法可以从 FileChannel 中将数据读到 Buffer 中，read 方法会返回一个 int 值表示有多少个字节被读到了 Buffer 中，如果返回 -1，说明到了文件末尾。从 Channel 读取数据的过程中会针对 Channel 进行同步处理。

```java
ByteBuffer byteBuffer = ByteBuffer.allocate(64);
int byteRead = fileChannel.read(byteBuffer);
```

下面是 FileChannel中 几个相关的 read 方法：
```java
// 读取数据到缓冲区
public abstract int read(ByteBuffer dst) throws IOException;

// 从指定的 position 处开始读取数据
public abstract int read(ByteBuffer dst, long position) throws IOException;

// 以 scatter 方式读取文件，即将文件内容读取到多个缓冲区
// offset 指定从哪个缓冲区开始写入，length 表示使用的缓冲区数量
public long read(ByteBuffer[] dsts, int offset, int length) throws IOException;

// 以 scatter 方式读取文件
public final long read(ByteBuffer[] dsts) throws IOException {
    return read(dsts, 0, dsts.length);
}
```
### 向 FileChannel 中写入数据
使用 write 方法，我们可以向 FileChannel 中写入数据，在写入的时候也会针对当前 Channel 进行同步处理。
```java
String newData = "data";
ByteBuffer byteBuffer = ByteBuffer.allocate(48);
byteBuffer.clear();
byteBuffer.put(newData.getBytes());

byteBuffer.flip();
while (byteBuffer.hasRemaining()) {
    channel.wirte(byteBuffer);
}
```
write 方法也有四种形式，含义和读取的时候类似
```java
// 将 Buffer 的数据写入 FileChannel
public abstract int write(ByteBuffer src) throws IOException;

// 将 Buffer 的数据写入 FileChannel，从 position 处开始写入
public abstract int write(ByteBuffer src, long position) throws IOException;

// 将多个 Buffer 的数据写入 FileChannel，gather 形式
public abstract long write(ByteBuffer[] srcs, int offset, int length) throws IOException;

// 将多个 Buffer 的数据写入 FileChannel
public final long write(ByteBuffer[] srcs) throws IOException {
    return write(srcs, 0, srcs.length);
}
```

### 关闭 FileChannel
使用完 FileChannel 之后需要调用 close 方法将其关闭
```java
channel.close();
```
下面是 close 方法的实现：
```java
public final void close() throws IOException {
    synchronized(closeLock) {
        if (!open)
            return;
        open = false;
        implCloseChannel();
    }
}
```

### position
有时候我们需要在 FileChannel 的某个特定位置进行读写操作，我们可以通过 position 方法获取和设置 FileChannel 的当前位置
```java
// 获得 FileChannel 当前的位置
long pos = channel.position();

// 设置 FileChannel 的当前位置
channel.position(pos + 123);
```
假设我们将位置设置在文件结束符之后，再次对 FileChannel 读写，会出现下面的结果：
* 调用 read 方法读取数据，会直接放回 -1，也就是文件结束标志
* 调用 write 方法写数据，文件将撑大到当前位置并写入数据。这有可能导致 [文件空洞](http://lisux.me/lishuai/?p=189)

### size
size 方法将返回 FileChannel 关联文件的大小：
```java
long fileSize = channel.size();
```
### truncate
使用 truncate 方法可以截取一个文件。截取文件时，文件中指定长度后面的部分将被删除：
```java
channel.truncate(1024);
```
上面的例子将会截取文件的前 1024 个字节。

### force
FileChannel 中的 force 方法会将 Channel 中没有写入磁盘的数据强制写到磁盘中。出于性能方面的考虑，操作系统会将数据缓存到内存中，所以无法保证写入到 FileChannel 中的数据一定会即时的写到磁盘中，如果我们需要保证这一点，就要调用 force 方法。force 方法有一个 boolean 类型的参数，指明是否同时将文件元数据（权限信息等）写入到磁盘中。
```java
channel.force(true);
```
### 文件锁定
通过 FileChannel 的 lock 和 tryLock 方法，我们可以对文件进行加锁。注意这里的文件锁是与具体的文件进行关联的，而不是 Channel 关联。文件锁主要是针对外部进程，也就说如果文件锁被一个进程获得，那么其他进程就无法再次访问该文件，但是获得锁进程内部的线程还是共享文件的。下面是 FileChannel 与锁相关的几个函数：
```java
// 从 position 位置开始，锁定 size 长度的内容，shared 表示锁是否是共享的
// 如果要获取共享锁，要以只读权限打开文件，如果想要获取独占锁，则需要写权限
// 如果获取不到锁，进程就会处于阻塞状态。
public abstract FileLock lock(long position, long size, boolean shared) throws IOException;

public final FileLock lock() throws IOException {
    return lock(0 L, Long.MAX_VALUE, false);
}

// 如果获取不到锁，会直接返回 null
public abstract FileLock tryLock(long position, long size, boolean shared) throws IOException;

public final FileLock tryLock() throws IOException {
    return tryLock(0 L, Long.MAX_VALUE, false);
}
```

下面是 FileLock 的几个方法：
```java
// 查询创建该锁的 FileChannel 对象
public final FileChannel channel()

// 释放锁
public abstract void release() throws IOException;

// 返回文件被锁住的起始位置
public final long position() {
    return position;
}

// 返回文件被锁住的大小
public final long size() {
    return size;
}

// 判断是否是共享锁
public final boolean isShared() {
    return shared;
}

// 判断锁是否有效
public abstract boolean isValid();

// 主要用于 try 代码块中自动关闭资源
public final void close() throws IOException {
    release();
}
```

### Zero Copy
[通过零拷贝实现有效数据传输](https://www.ibm.com/developerworks/cn/java/j-zerocopy/)

## Socket Channel
Socket 通道主要处理网络数据流，主要有下面 3 个类：
* ServerSocketChannel - 服务器套接字通道，用于 TCP 协议，监听传入的连接以及创建新的 SocketChannel 对象。ServerSocketChannel 本身不传输数据。
* SocketChannel - 套接字通道，用于 TCP 协议。当客户端连接到服务器之后，服务器和客户端都会有一个 SocketChannel，两者通过 SocketChannel 进行通信。
* DatagramChannel - 数据报通道，用于 UDP 协议。

Socket 通道可以以非阻塞模式运行，极大的提高了程序的性能，下面是相关方法：
```java
// block=false：非阻塞模式；block=true：阻塞模式
public abstract SelectableChannel configureBlocking(boolean block) throws IOException;

// 查询当前通道是否处于阻塞模式
public abstract boolean isBlocking();
```
### ServerSocketChannel
ServerSocketChannel 是一个基于通道的 socket 监听器，它主要用来监听传入的请求，并为该请求创建一个关联的 SocketChannel 对象，服务器和客户端最终还是通过 SocketChannel 对象进行传输数据的。
```java
// 创建 ServerSocketChannel 对象，只能同静态的 open 方法创建
ServerSocketChannel serverSocketChannel = ServerSocketChannel.open();

// 绑定监听地址，ServerSocketChannel 对象本身无法设置监听地址，
// 需要通过其关联的 ServerSocket 对象来设置
serverSocketChannel.socket().bind(new InetSocketAddress(port));

// 设为非阻塞模式
serverSocketChannel.configureBlocking(false);

while (true) {
	// accept 用来监听新的连接，因为是非阻塞模式，没有链接会返回 null
    SocketChannel socketChannel = serverSocketChannel.accept();
}
```
### SocketChannel
我们通过 SocketChannel 来传输数据，每个 SocketChannel 对象都会关联一个 Socket 对象，我们有两种方式获得 SocketChannel
* 调用 SocketChannel 的 open 方法
* 当一个新连接到达 ServerSocketChannel 时，会创建一个 SocketChannel

通过 open 方法获得 SocketChannel 对象需要连接之后才能使用，如果对个未连接的 SocketChannel 对象执行 IO 操作，会抛出 NotYetConnectedException，下面是一个使用示例：
```java
String host = "localhost";
int port = 1234;
InetSocketAddress address = new InetSocketAddress(host, port);

// 创建 SocketChannel 对象
SocketChannel socketChannel = SocketChannel.open();

// 设为非阻塞模式
socketChannel.configureBlocking(false);

// 链接服务器
socketChannel.connect(address);

// 判断是否已经建立连接
while (!socketChannel.finishConnect()) {
	// 在建立连接的过程中可以做一些其他的操作
    System.out.println("do other things...");
}

ByteBuffer buffer = ByteBuffer.allocate(100);
int readLen;

// 这里采用了非阻塞模式，因此 read 方法可能会直接返回 0，
// 即没有读到内容。但是只有读到 -1 时，才表明 socket 中
// 的数据已经读取完毕
while ((readLen = socketChannel.read(buffer)) != -1) {
    if (readLen != 0) {
        String result = new String(buffer.array()).trim();
        System.out.println(result);
    }
}

// 关闭 socketChannel
socketChannel.close();
```
Socket 是面向流（stream-oriented）的，而不是面向包（packet-oriented）的，它只能保证发送的字节会按照顺序到达，但是无法保证同时维持字节分组，假设向 socket 中传入了 20 个字节，那么调用 read 方法有可能只能读到 3 个字节，而剩余的 17 个字节还在传输中。

下面是 SokcetChannel 中的一些方法：

```java
// 判断是否完成连接过程
public abstract boolean finishConnect() throws IOException;

// 判断是否建立了连接
public abstract boolean isConnected();

// 判断当前 Channel 是否正在建立连接
public abstract boolean isConnectionPending();

// 从 Channel 读取数据到 Buffer
public abstract int read(ByteBuffer dst) throws IOException;

// 从 Channel 读取数据到 多个 Buffer
public abstract long read(ByteBuffer[] dsts, int offset, int length) throws IOException;

public final long read(ByteBuffer[] dsts) throws IOException {
    return read(dsts, 0, dsts.length);
}

// 将 Buffer 中的数据写入到 Channel
public abstract int write(ByteBuffer src) throws IOException;

// 将多个 Buffer 中的数据写入到 Channel
public abstract long write(ByteBuffer[] srcs, int offset, int length) throws IOException;

public final long write(ByteBuffer[] srcs) throws IOException {
    return write(srcs, 0, srcs.length);
}
```
### DatagramChannel
DatagramChannel 主要通过 UDP 传输数据。UDP 是无连接的网络协议，所以 DatagramChannel 发送和接收的都是数据包，每个数据包都是一个独立的实体，包含自己的目标地址。DatagramChannel 对象既可以充当服务器，也可以充当客户端，如果希望 DatagramChannel 作为服务端，需要首先为其绑定一个地址。下面是一个示例：

> Server

```java
// 创建 DatagramChannel
DatagramChannel datagramChannel = DatagramChannel.open();

// 绑定地址监听，作为服务端
datagramChannel.socket().bind(new InetSocketAddress(1111));
ByteBuffer buffer = ByteBuffer.allocate(64);
while (true) {
    // 接受客户端发送过来的数据，如果数据的长度大于
    // Buffer 的空间，那么多余的数据会被丢弃
    // receive 方法会返回一个 SocketAddress 对象以指明数据来源
    datagramChannel.receive(buffer);
    buffer.flip();
    while (buffer.hasRemaining()) {
        System.out.write(buffer.get());
    }
    System.out.println();
    buffer.clear();
}
```

> Client

```java
List < String > textList = new ArrayList < > (
    Arrays.asList("1111", "2222", "3333", "4444")
);
InetAddress hostIP = InetAddress.getLocalHost();
InetSocketAddress address = new InetSocketAddress(hostIP, 1111);

// 创建 DatagramChannel
DatagramChannel datagramChannel = DatagramChannel.open();
datagramChannel.bind(null);

ByteBuffer buffer = ByteBuffer.allocate(64);
for (String text: textList) {
    System.out.println("sending msg: " + text);
    buffer.put(text.getBytes());
    buffer.flip();

    //  发送数据时要指定目标地址
    datagramChannel.send(buffer, address);
    buffer.clear();
}
```

在阻塞模式下，receive 方法可能无限期的休眠直到有数据包到达，而处于非阻塞模式下时，当没有可接收的数据包时会返回 null。

通过调用 connect 方法，可以连接一个 DatagramChannel，这里的连接只是绑定了一个 DatagramChannel，实际上并没有建立连接。当两个 DatagramChannel 处于连接状态时，它们只能相互通信。使用 disconnect 方法可以断开连接。

下面是使用数据报的情形：
* Your application can tolerate lost or out-of-order data.
* You want to fire and forget and don't need to know if the packets you sent were received.
* Throughput is more important than reliability.
* You need to send to multiple receivers (multicast or broadcast) simultaneously.
* The packet metaphor fits the task at hand better than the stream metaphor.
