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

```
