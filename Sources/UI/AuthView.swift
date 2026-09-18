import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var phone = ""
    @State private var code = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                switch environment.authState {
                case .waitPhoneNumber, .unknown, .closed:
                    phoneStep
                case .waitCode(let number):
                    codeStep(number: number)
                case .waitPassword(let hint):
                    passwordStep(hint: hint)
                case .waitRegistration:
                    infoStep(text: "Этот номер ещё не зарегистрирован в Telegram. Регистрацию нужно пройти в официальном приложении — сторонним клиентам Telegram это не разрешает.")
                case .loggingOut:
                    infoStep(text: "Выходим из аккаунта…")
                default:
                    ProgressView()
                }

                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                if environment.telegram.isDemo {
                    demoHint
                }
            }
            .padding(24)
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 54))
                .foregroundStyle(CasperTheme.ghostGradient)
            Text("Casper")
                .font(.largeTitle.bold())
            Text("Неофициальный клиент Telegram")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 36)
    }

    private var phoneStep: some View {
        VStack(spacing: 14) {
            TextField("+7 900 000-00-00", text: $phone)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .multilineTextAlignment(.center)
                .font(.title3)
                .padding()
                .casperSurface(cornerRadius: 16)

            Button {
                run { try await environment.telegram.sendPhoneNumber(phone) }
            } label: {
                Label("Получить код", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(phone.count < 5 || isBusy)

            Text("Casper запрашивает код через официальный Telegram API. Пароль от облака и код подтверждения никуда, кроме серверов Telegram, не отправляются.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func codeStep(number: String) -> some View {
        VStack(spacing: 14) {
            Text(number.isEmpty ? "Введите код из Telegram" : "Код отправлен на \(number)")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("12345", text: $code)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .padding()
                .casperSurface(cornerRadius: 16)

            Button {
                run { try await environment.telegram.sendAuthCode(code) }
            } label: {
                Label("Войти", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(code.count < 4 || isBusy)
        }
    }

    private func passwordStep(hint: String) -> some View {
        VStack(spacing: 14) {
            Text(hint.isEmpty ? "Введите пароль двухфакторной защиты" : "Подсказка: \(hint)")
                .font(.callout)
                .foregroundStyle(.secondary)

            SecureField("Пароль", text: $password)
                .textContentType(.password)
                .padding()
                .casperSurface(cornerRadius: 16)

            Button {
                run { try await environment.telegram.sendPassword(password) }
            } label: {
                Label("Продолжить", systemImage: "lock.open.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(password.isEmpty || isBusy)
        }
    }

    private func infoStep(text: String) -> some View {
        Text(text)
            .font(.callout)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
    }

    private var demoHint: some View {
        VStack(spacing: 6) {
            Label("Демо-режим", systemImage: "wrench.and.screwdriver.fill")
                .font(.caption.weight(.semibold))
            Text("TDLib не подключён к сборке, поэтому Telegram недоступен. Любой номер и код \(MockTelegramService.demoCode) откроют интерфейс с демо-данными.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .casperSurface(cornerRadius: 16)
    }

    private func run(_ action: @escaping () async throws -> Void) {
        isBusy = true
        error = nil
        Task {
            do {
                try await action()
            } catch {
                self.error = error.localizedDescription
            }
            isBusy = false
        }
    }
}
