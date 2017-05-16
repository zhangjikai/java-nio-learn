# Selector

<!-- toc -->

Selector （选择器）是实现异步 IO 的核心。Selector 提供了就绪选择（readiness select）的功能，当 Channel 就绪之后，会触发相关事件并通知 Selector，我们可以通过 Selector 选择触发相关事件的 Channel 并进行处理。就绪选择的真正价值在于多个通道可以同时进行就绪状态的检查，因此即便是用单个线程，我们也可以很好的处理多个通道。

![](/images/nio_selector.png)
> 图片来自 https://avaldes.com/java-nio-selectors-using-nio-client-server-example/

## 基础
Selector 相关的有三个基本的类：
* Selector - Selector 类主要管理已经注册的 Channel 集合以及它们的就绪状态
* SelectableChannel - Channel 可以被选择的前提是它是一个可被选择的 Channel，也就是要继承该类。FileChannel 是不可被选择的，所有的 Socket Channel 都是可选择的
* SelectorKey - 该类封装了 Selector 和 Channel 的注册关系，SelectionKey 包含关联 Selector 和 Channel 信息

在使用 Selector 管理 Channel 之前，需要先将 Channel 注册到相关的 Selector 上，在注册 Channel 时还需要指定对 Channel 感兴趣的事件类型，下面是 Channel 的支持的事件类型：

```java
// 读事件，表示 buffer 可读
public static final int OP_READ = 1 << 0;

// 写事件，表示 buffer 可写
public static final int OP_WRITE = 1 << 2;

// socket 连接事件（TCP）
public static final int OP_CONNECT = 1 << 3;

// socket 接收事件
public static final int OP_ACCEPT = 1 << 4;
```
## 示例
下面是一个基本示例：
```java
// 通过 open 方法创建 channel
Selector selector = Selector.open();
channel.configureBlocking(false);

// 将 Channel 注册到 Selector 上，这里我们感兴趣的事件是读事件
// 也就是说只有 Channel 可读了，才会通知 Selector，如果想要注册
// 多个感兴趣的事件，可以使用 |，如 SelectionKey.OP_READ | SelectionKey.OP_WRITE
SelectionKey key = channel.register(selector, SelectionKey.OP_READ);

// 在循环中处理请求
while (true) {

    // 获得已经就绪的通道数量，这里的 select 方法会阻塞线程，
    // 一般来说当有通道就绪之后才会继续往下执行，但是有可能
    // 会出现虚假唤醒的情况（spurious wakeup）,所以下面会对就绪的
    // 通道数量再做一次判断
    int readyChannels = selector.select();
    if (readyChannels == 0)
        continue;

    // 获得就绪的事件对应的 SelectedKey，SelectedKey 中
    // 包含了事件类型以及对应的 Selector 和 Channel 信息
    Set selectedKeys = selector.selectedKeys();
    Iterator keyIterator = selectedKeys.iterator();

    // 遍历事件集合
    while (keyIterator.hasNext()) {
        SelectionKey key = keyIterator.next();

        // 针对不同的事件进行处理
        if (key.isAcceptable()) {
            // a connection was accepted by a ServerSocketChannel.
        } else if (key.isConnectable()) {
            // a connection was established with a remote server.
        } else if (key.isReadable()) {
            // a channel is ready for reading
        } else if (key.isWritable()) {
            // a channel is ready for writing
        }
        // 将当前事件从迭代器中移除
        keyIterator.remove();
    }
}
```
在 Channel 支持的事件中，Acceptable 是针对 ServerSocket 的，而其余三个事件是针对 Socket的。注意, 在每次迭代时, 我们都调用 "keyIterator.remove()" 将这个 key 从迭代器中删除, 因为 select() 方法仅仅是简单地将就绪的 IO 事件放到 selectedKeys 集合中, 因此如果我们从 selectedKeys 获取到一个 key, 但是没有将它删除, 那么下一次 select 时, 这个 key 所对应的 IO 事件还在 selectedKeys 中.

我们知道调用 select 方法会阻塞当前线程，如果没有 Channel 就绪，我们又想唤醒线程，额可以使用 wakeup 方法。当调用  wakeup 方法之后，会立即唤醒当前线程。

当用完 Selector 后，我们可以使用 close 方法关闭该 Selector。

## 服务器和客户端
> 服务端

```java
import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.ByteBuffer;
import java.nio.channels.SelectionKey;
import java.nio.channels.Selector;
import java.nio.channels.ServerSocketChannel;
import java.nio.channels.SocketChannel;
import java.util.Iterator;

/**
 * Created by Jikai Zhang on 2017/5/13.
 */
public class SocketServer {

    public static void main(String[] args) throws IOException {
        String address = "localhost";
        int port = 1234;
        ServerSocketChannel channel = ServerSocketChannel.open();
        channel.socket().bind(new InetSocketAddress(address, port));
        Selector selector = Selector.open();
        channel.configureBlocking(false);
        channel.register(selector, SelectionKey.OP_ACCEPT);

        while (true) {
            //System.out.println(1111);
            selector.select();
            Iterator<SelectionKey> iterator = selector.selectedKeys().iterator();
            while (iterator.hasNext()) {
                SelectionKey key = iterator.next();
                iterator.remove();
                handleKey(key, selector);
            }
        }
    }


    public static void handleKey(SelectionKey key, Selector selector) throws IOException {
        ServerSocketChannel server = null;
        SocketChannel client = null;
        if(key.isAcceptable()) {
            System.out.println("Acceptable");
            server = (ServerSocketChannel) key.channel();
            // 这里建立连接，创建了新的 SocketChannel，需要将该 Channel
            // 注册到 Selector 上
            client = server.accept();
            client.configureBlocking(false);
            client.register(selector, SelectionKey.OP_READ);
        } else if(key.isReadable()) {
            client = (SocketChannel) key.channel();
            ByteBuffer byteBuffer = ByteBuffer.allocate(200);
            int count = client.read(byteBuffer);
            if(count > 0) {
                System.out.println("Readable");
                System.out.println(new String(byteBuffer.array()));
            } else if(count == -1) {
                key.cancel();
                return;
            }
        }
    }
}
```
> 客户端

```java
import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.ByteBuffer;
import java.nio.channels.SelectionKey;
import java.nio.channels.Selector;
import java.nio.channels.SocketChannel;
import java.util.Iterator;

/**
 * Created by Jikai Zhang on 2017/5/13.
 */
public class SocketClient {
    public static void main(String[] args) throws IOException {
        String address = "localhost";
        int port = 1234;
        SocketChannel channel = SocketChannel.open();
        channel.configureBlocking(false);
        channel.connect(new InetSocketAddress(address, port));

        Selector selector = Selector.open();
        channel.register(selector, SelectionKey.OP_CONNECT);

        while(true) {
            selector.select();
            Iterator<SelectionKey> iterator = selector.selectedKeys().iterator();
            while(iterator.hasNext()) {
                SelectionKey key = iterator.next();
                iterator.remove();
                if(key.isConnectable()) {
                    handle(key, selector);
                }
            }
        }
    }

    static void handle(SelectionKey key, Selector selector) throws IOException {
        SocketChannel client = (SocketChannel) key.channel();
        if(client.isConnectionPending()) {
            if(client.finishConnect()) {
                ByteBuffer byteBuffer = ByteBuffer.allocate(200);
                byteBuffer = ByteBuffer.wrap(new String("hello server").getBytes());
                client.write(byteBuffer);
                client.register(selector, SelectionKey.OP_READ);
            }
        } else if(key.isReadable()) {

        }
    }
}

```
