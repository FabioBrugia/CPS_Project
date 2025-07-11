clc;
clear all;
close all;

fprintf('Multi-Agent Magnetic Levitation System\n');

% Define parameter ranges to test
Q_values = {eye(2), 2*eye(2), 100*eye(2)};
R_values = [0.1, 1, 100];
noise_levels = [0, 0.01, 0.05];
rng(42)
c_weigth =[5, 10 , 100]';
T_sim = 10;

% Agents
N = 6;
A = [0 1; 880.87 0];
B = [0; -9.9453];
C = [708.27 0];
D = zeros(1, 2);
runs = {};
exp_num = 1;

% Select a single topology
topology_type = 'star';
[Adj, G, L] = create_network_topology(N, topology_type);

% Nested loops for Q, R, and noise

Q = Q_values{1};
R = R_values(2);
noise_level = noise_levels(1);
noise_freq = 0.1;

fprintf('\nExperiment %d: Q=%.1f*I, R=%.2f, noise=%.3f\n', ...
    exp_num, trace(Q)/2, R, noise_level);
exp_num = exp_num + 1;
%for w = 1:length(c_weigth)
    %for ref_cell = {'const', 'ramp', 'sin'}
        reference = 'sin';
        
        % --- Reference-dependent setup ---
        switch reference
            case 'const'
                R0 = 1;
                x0_0 = [R0; 0];
                K0 = place(A, B, [0, -20]);
            case 'ramp'
                slope = 1;
                K0 = acker(A, B, [0 0]);
                x0_0 = [0; slope];
            case 'sin'
                w0 = 1;
                Amp = 1;
                K0 = place(A, B, [w0*1i, -w0*1i]);
                x0_0 = [Amp; 0];
        end
        
        A0 = A - B * K0;
        L0 = place(A0', C', [-10, -20])';
        
        perturb = @(v) 0.5 * randn(size(v));
        x0_1 = perturb(x0_0);
        x0_2 = perturb(x0_0);
        x0_3 = perturb(x0_0);
        x0_4 = perturb(x0_0);
        x0_5 = perturb(x0_0);
        x0_6 = perturb(x0_0);
        
        x0_hat = [0; 0];
        
        % Compute coupling gain c
        eig_LG = eig(L + G);
        cmin = 1/2 * (1 / min(real(eig_LG)));
        c = cmin*2;
        
        % Distributed Controller Riccati Equation
        Pc = are(A0, B * R^(-1) * B', Q);
        K = R^(-1) * B' * Pc;
        
        % Cooperative Observer F
        P = are(A0', C' * R^(-1) * C, Q);
        F_c = P * C' * R^(-1);
        
        % Local Observer F
        F_l = find_hurwitz_F(A0, C, c);
        
        % Check if Ao is Hurwitz for the Cooperative Observer
        Ao_coop = kron(eye(N), A0) - c * kron(L + G, F_c * C);
        eigvals_Ao_coop = eig(Ao_coop);
        if any(real(eigvals_Ao_coop) >= 0)
            error('Ao Cooperative NOT Hurwitz: at least one eigenvalue has a real part >= 0.');
        end
        
        % Check if Ao is Hurwitz for the Local Observer
        Ao_local = A0 + c * F_l * C;
        eigvals_Ao_local = eig(Ao_local);
        if any(real(eigvals_Ao_local) >= 0)
            error('Ao Local NOT Hurwitz: at least one eigenvalue has a real part >= 0.');
        end
        
        threshold = 2e-4;
        
        % Cooperative Observer Results
        results_cooperative = sim('cooperative_observer.slx');
        x_hat_all = results_cooperative.x_hat_all.Data;  % [12 x 1 x N]
        x_ref_col = results_cooperative.x_ref_col.Data;  % [12 x 1 x N]
        t = results_cooperative.tout;                    % [Nx1]
        y_i_all = results_cooperative.y_i_all.Data; % [6 x 1 x N]
        y_ref = results_cooperative.y_ref.Data;% [6 x 1 x N]
        state_estimation_error_cooperative = abs(squeeze(x_ref_col - x_hat_all));
        [t_conv_cooperative, idx_c] = time_to_conv(state_estimation_error_cooperative, t, threshold);
        % plot_agent_states_vs_ref(x_hat_all,x_ref_col,t,'cooperative');
        % plot_estimation_errors_by_state(x_hat_all,x_ref_col,t,'cooperative')
        plot_agent_outputs(y_i_all,y_ref,t,'cooperative',Q,R,noise_level,c);
        % Local Observer Results
        results_local = sim('local_observer.slx');
        x_hat_all = results_local.x_hat_all.Data;
        x_ref_col = results_local.x_ref_col.Data;
        t = results_local.tout;
        y_i_all = results_local.y_i_all.Data; % [6 x 1 x N]
        y_ref = results_local.y_ref.Data;% [6 x 1 x N]
        % plot_agent_outputs(y_i_all,y_ref,t,'local',Q,R,noise_level,c);
        state_estimation_error_local = abs(squeeze(x_ref_col - x_hat_all));
        [t_conv_local, idx_l] = time_to_conv(state_estimation_error_local, t, threshold);
        

        % plot_agent_states_vs_ref(x_hat_all,x_ref_col,t,'local');
        % plot_estimation_errors_by_state(x_hat_all,x_ref_col,t,'local')
        % Save all the data
        run = struct();
        run.topology_type = topology_type;
        run.reference = reference;
        run.R = R;
        run.Q = Q;
        run.c = c;
        run.noise_level = noise_level;
        run.F_c = F_c;
        run.F_l = F_l;
        
        if ~isnan(idx_c)
            run.see_coop = max(state_estimation_error_cooperative(:,idx_c));
        else
            run.see_coop = max(state_estimation_error_cooperative(:,end));
        end
        
        if ~isnan(idx_l)
            run.see_local = max(state_estimation_error_local(:,idx_l));
        else
            run.see_local = max(state_estimation_error_local(:,end));
        end
        
        run.t_coop = t_conv_cooperative;
        run.t_local = t_conv_local;
        
        runs{end+1} = run;
        
        % Print brief results for each reference
        fprintf('  %s: Coop T_conv=%.2f, Local T_conv=%.2f\n', ...
            reference, t_conv_cooperative, t_conv_local);
    %end
%end

% Display detailed results
fprintf('\n--- DETAILED RESULTS ---\n');
for i = 1:length(runs)
    fprintf('\n--- Run %d ---\n', i);
    disp(runs{i});
end

fprintf('End\n');